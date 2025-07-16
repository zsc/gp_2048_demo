# app.py
import os
import random
import json
import threading
from datetime import datetime
from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO, emit
from tqdm import tqdm

# Import our custom modules
from game import Game2048
from gp_engine import GPEngine, Program, evaluate_fitness_worker, Add, Sub, Mul, SafeDiv, IfLTE, \
                       Constant, NumEmptyCells, MaxTileValue, MonotonicityScore, SmoothnessScore

# --- Flask & Socket.IO Setup ---
app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
# Allow large messages for potentially complex programs
socketio = SocketIO(app, async_mode='threading', max_http_buffer_size=1e7)

# --- Global State Management ---
training_thread = None
stop_training_event = threading.Event()
MODELS_DIR = "models"
if not os.path.exists(MODELS_DIR):
    os.makedirs(MODELS_DIR)

# --- GP Program Serialization/Deserialization ---

# A factory to map string names back to class instances
NODE_FACTORY = {
    # Functions
    "ADD": Add, "SUB": Sub, "MUL": Mul, "DIV": SafeDiv, "IFLTE": IfLTE,
    # Terminals
    "EMPTY": NumEmptyCells, "MAX_TILE": MaxTileValue, "MONO": MonotonicityScore, "SMOOTH": SmoothnessScore
}

def serialize_program(program: Program) -> str:
    """Converts a Program object into a JSON string."""
    node_list = []
    for node in program.nodes:
        node_dict = {'name': node.name, 'arity': node.arity}
        if isinstance(node, Constant):
            node_dict['type'] = 'Constant'
            node_dict['value'] = node.value
        elif node.name in NODE_FACTORY:
            node_dict['type'] = 'BuiltIn'
        else:
            raise TypeError(f"Unknown node type for serialization: {node}")
        node_list.append(node_dict)
    return json.dumps(node_list)

def deserialize_program(json_str: str) -> Program:
    """Reconstructs a Program object from a JSON string."""
    node_list_data = json.loads(json_str)
    nodes = []
    for node_data in node_list_data:
        if node_data.get('type') == 'Constant':
            nodes.append(Constant(value=node_data['value']))
        elif node_data.get('type') == 'BuiltIn':
            node_class = NODE_FACTORY.get(node_data['name'])
            if node_class:
                nodes.append(node_class())
            else:
                raise ValueError(f"Unknown node name in factory: {node_data['name']}")
        else:
            raise ValueError(f"Invalid node data for deserialization: {node_data}")
    return Program(nodes)

# --- Training Logic (executed in a background thread) ---
def training_wrapper(params: dict, sid: str):
    """
    A wrapper to run the GP evolution and communicate progress via Socket.IO.
    This function contains a modified version of GPEngine.run() to allow
    for real-time updates and graceful stopping without altering gp_engine.py.
    """
    global stop_training_event
    stop_training_event.clear()

    run_id = datetime.now().strftime("run_%Y%m%d_%H%M%S")
    log_dir = os.path.join('runs', run_id)
    
    try:
        engine = GPEngine(
            population_size=int(params['population_size']),
            generations=int(params['generations']),
            crossover_rate=float(params['crossover_rate']),
            mutation_rate=float(params['mutation_rate']),
            tournament_size=int(params['tournament_size']),
            max_init_depth=int(params['max_init_depth']),
            max_depth=int(params['max_depth']),
            elitism_size=int(params['elitism_size']),
            games_per_individual=int(params['games_per_individual']),
            log_dir=log_dir
        )
        socketio.emit('training_update', {'log': f"TensorBoard log directory: {log_dir}"}, to=sid)
        
        socketio.emit('training_update', {'log': "Initializing population..."}, to=sid)
        engine._initialize_population()
        socketio.sleep(0.1)

        for gen in range(engine.generations):
            if stop_training_event.is_set():
                socketio.emit('training_update', {'log': "Training stopped by user."}, to=sid)
                break
            
            gen_log_header = f"\n--- Generation {gen+1}/{engine.generations} ---"
            socketio.emit('training_update', {'log': gen_log_header}, to=sid)
            
            # Evaluate fitness in parallel
            socketio.emit('training_update', {'log': "Evaluating fitness..."}, to=sid)
            # We cannot easily show a progress bar here, so we just wait. The arguments
            # must be prepared for the top-level evaluate_fitness_worker function.
            eval_args = [(p, engine.games_per_individual) for p in engine.population]
            results = list(engine.pool.imap(evaluate_fitness_worker, eval_args))
            engine.population = results
            
            engine.population.sort(key=lambda p: p.fitness, reverse=True)
            best_program = engine.population[0]
            avg_fitness = sum(p.fitness for p in engine.population) / engine.population_size
            avg_game_score = sum(p.game_score for p in engine.population) / engine.population_size
            
            # Prepare stats for frontend and TensorBoard
            stats = {
                'generation': gen + 1,
                'total_generations': engine.generations,
                'best_fitness': f"{best_program.fitness:.2f}",
                'avg_fitness': f"{avg_fitness:.2f}",
                'best_score': f"{best_program.game_score:.0f}",
                'avg_score': f"{avg_game_score:.0f}",
                'best_max_tile': f"{best_program.max_tile:.0f}",
                'best_program_str': str(best_program),
            }
            log_msg = (f"Best Fitness: {stats['best_fitness']} | "
                       f"Avg Fitness: {stats['avg_fitness']} | "
                       f"Best Game Score: {stats['best_score']}")
            socketio.emit('training_update', {'log': log_msg, 'stats': stats}, to=sid)

            engine.writer.add_scalar('Fitness/Best', best_program.fitness, gen)
            engine.writer.add_scalar('Fitness/Average', avg_fitness, gen)
            # ... (other tensorboard logging from original run method) ...
            
            # Create the next generation
            next_generation = []
            if engine.elitism_size > 0:
                next_generation.extend(engine.population[:engine.elitism_size])

            while len(next_generation) < engine.population_size:
                p1 = engine._tournament_selection()
                if random.random() < engine.crossover_rate:
                    p2 = engine._tournament_selection()
                    c1, c2 = engine._crossover(p1, p2)
                else:
                    c1, c2 = p1, None
                if random.random() < engine.mutation_rate:
                    c1 = engine._mutate(c1)
                next_generation.append(c1)
                if c2 and len(next_generation) < engine.population_size:
                    if random.random() < engine.mutation_rate:
                        c2 = engine._mutate(c2)
                    next_generation.append(c2)
            
            engine.population = next_generation
            socketio.sleep(0.1) # Yield to other threads

        # --- Cleanup and Save ---
        engine.pool.close()
        engine.pool.join()
        engine.writer.close()
        
        final_best_program = sorted(results, key=lambda p: p.fitness, reverse=True)[0]
        model_filename = f"{run_id}_best.json"
        model_path = os.path.join(MODELS_DIR, model_filename)
        with open(model_path, 'w') as f:
            f.write(serialize_program(final_best_program))
            
        socketio.emit('training_update', {'log': f"\nEvolution finished. Best program saved to {model_path}"}, to=sid)

    except Exception as e:
        socketio.emit('training_update', {'log': f"\nAn error occurred: {e}"}, to=sid)
        import traceback
        traceback.print_exc()
    finally:
        socketio.emit('training_finished', {'new_model': model_filename}, to=sid)

# --- Flask Routes and Socket.IO Handlers ---

@app.route('/')
def index():
    """Serve the main HTML page."""
    return render_template('index.html')

@app.route('/api/models', methods=['GET'])
def get_models():
    """Provide a list of saved model files."""
    try:
        models = [f for f in os.listdir(MODELS_DIR) if f.endswith('.json')]
        return jsonify(sorted(models, reverse=True))
    except FileNotFoundError:
        return jsonify([])

@socketio.on('connect')
def handle_connect():
    print(f"Client connected: {request.sid}")
    # Initialize the game logic tables if not already done
    Game2048._init_tables()

@socketio.on('disconnect')
def handle_disconnect():
    print(f"Client disconnected: {request.sid}")

@socketio.on('start_training')
def handle_start_training(params):
    """Starts the GP training in a new thread."""
    global training_thread
    if training_thread and training_thread.is_alive():
        emit('training_update', {'log': 'A training session is already in progress.'})
        return

    emit('training_update', {'log': 'Received training request. Starting...'})
    training_thread = socketio.start_background_task(
        target=training_wrapper, params=params, sid=request.sid
    )

@socketio.on('stop_training')
def handle_stop_training():
    """Signals the training thread to stop."""
    global stop_training_event
    if training_thread and training_thread.is_alive():
        stop_training_event.set()
        emit('training_update', {'log': 'Stop signal sent. Waiting for current generation to finish...'})
    else:
        emit('training_update', {'log': 'No active training session to stop.'})

@socketio.on('request_new_game')
def handle_new_game():
    """Provides a new 2048 board."""
    board_int = Game2048.reset_board()
    emit('new_game_state', {'board': str(board_int), 'score': 0, 'max_tile': 0, 'is_over': False})

@socketio.on('request_next_move')
def handle_next_move(data):
    """
    Given a board state and a model, calculates and returns the best move.
    """
    try:
        model_file = data['model']
        board_int = int(data['board'])
        
        with open(os.path.join(MODELS_DIR, model_file), 'r') as f:
            program = deserialize_program(f.read())
            
        move_fns = {
            0: Game2048.move_up, 
            1: Game2048.move_down, 
            2: Game2048.move_left, 
            3: Game2048.move_right
        }
        
        best_move_idx = -1
        best_eval_score = -float('inf')
        
        possible_moves = []
        for i, move_fn in move_fns.items():
            next_board, _, moved = move_fn(board_int)
            if moved:
                eval_score = program.eval(next_board)
                possible_moves.append({'move': i, 'score': eval_score})
                if eval_score > best_eval_score:
                    best_eval_score = eval_score
                    best_move_idx = i

        if best_move_idx != -1:
            # Execute the best move to get the new state
            new_board, score_gain, _ = move_fns[best_move_idx](board_int)
            new_board_with_tile = Game2048.add_random_tile(new_board)
            is_over = Game2048.is_game_over(new_board_with_tile)
            max_tile = Game2048.get_max_tile(new_board_with_tile)
            
            emit('next_move_result', {
                'move': best_move_idx,
                'score_gain': score_gain,
                'new_board': str(new_board_with_tile),
                'is_over': is_over,
                'max_tile': max_tile
            })
        else:
            # Game is over, no moves possible
            emit('next_move_result', {'move': -1, 'is_over': True})

    except Exception as e:
        emit('error', {'message': f'Error processing move: {e}'})
        import traceback
        traceback.print_exc()

if __name__ == '__main__':
    print("Starting GP 2048 Demo Server...")
    print("Open http://127.0.0.1:5000 in your browser.")
    socketio.run(app, host='0.0.0.0', port=5005, debug=True, allow_unsafe_werkzeug=True)
