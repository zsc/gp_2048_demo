# app.py - Flask server with OCaml backend for fast 2048 AI
import os
import random
import json
import threading
import subprocess
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

# Path to OCaml inference CLI
OCAML_INFERENCE_PATH = "../_build/default/inference_cli.exe"

# --- Global State Management ---
training_thread = None
stop_training_event = threading.Event()
MODELS_DIR = "models"
if not os.path.exists(MODELS_DIR):
    os.makedirs(MODELS_DIR)

# --- Experiment Results for Display ---
EXPERIMENT_RESULTS = {
    "node_limited_50_games": {
        "title": "Node-Limited Expectimax (50 games, 6 cores)",
        "data": [
            {"budget": 100, "avg_score": 4998, "std_dev": 2481, "max_score": 11972, "games_per_sec": 69.5},
            {"budget": 500, "avg_score": 5057, "std_dev": 2010, "max_score": 11960, "games_per_sec": 29.2},
            {"budget": 1000, "avg_score": 4844, "std_dev": 2139, "max_score": 11908, "games_per_sec": 16.6},
            {"budget": 5000, "avg_score": 5100, "std_dev": 1944, "max_score": 11164, "games_per_sec": 11.3},
            {"budget": 10000, "avg_score": 4651, "std_dev": 1973, "max_score": 10552, "games_per_sec": 6.3},
            {"budget": 50000, "avg_score": 4982, "std_dev": 2197, "max_score": 13704, "games_per_sec": 1.3}
        ]
    },
    "performance_comparison": {
        "title": "OCaml vs Python Performance",
        "data": {
            "board_operations": {"python": 450347, "ocaml": 85120325, "speedup": 189},
            "expectimax_depth1": {"python": 846, "ocaml": 31547, "speedup": 37},
            "expectimax_depth2": {"python": 11, "ocaml": 421, "speedup": 37},
            "expectimax_depth3": {"python": 0.15, "ocaml": 5.1, "speedup": 34},
            "full_game_depth1": {"python": 35.5, "ocaml": 1129, "speedup": 32},
            "full_game_depth2": {"python": 0.4, "ocaml": 15.7, "speedup": 36}
        }
    },
    "lookup_table_speedup": {
        "title": "Lookup Table Optimization",
        "data": {
            "evaluation_functions": {"original": 0.087, "with_lut": 0.008, "speedup": 10.7},
            "gp_tree_evaluation": {"original": 1028066, "with_lut": 5636748, "speedup": 5.5}
        }
    }
}

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
    
    program_data = {
        'nodes': node_list,
        'fitness': program.fitness,
        'games_played': program.games_played,
        'avg_score': program.avg_score,
        'avg_max_tile': program.avg_max_tile
    }
    return json.dumps(program_data, indent=2)

def deserialize_program(program_json: str) -> Program:
    """Converts a JSON string back into a Program object."""
    program_data = json.loads(program_json)
    
    nodes = []
    for node_dict in program_data['nodes']:
        if node_dict['type'] == 'Constant':
            nodes.append(Constant(node_dict['value']))
        elif node_dict['type'] == 'BuiltIn':
            node_name = node_dict['name']
            if node_name in NODE_FACTORY:
                nodes.append(NODE_FACTORY[node_name])
            else:
                raise ValueError(f"Unknown built-in node: {node_name}")
        else:
            raise ValueError(f"Unknown node type: {node_dict['type']}")
    
    program = Program(nodes)
    program.fitness = program_data.get('fitness', 0.0)
    program.games_played = program_data.get('games_played', 0)
    program.avg_score = program_data.get('avg_score', 0.0)
    program.avg_max_tile = program_data.get('avg_max_tile', 0.0)
    
    return program

# --- OCaml Backend Integration ---

def get_ocaml_move(board_int, model_path=None):
    """Call OCaml inference CLI to get the best move"""
    try:
        # Convert board to hex string
        board_hex = hex(board_int)
        
        # Build command
        cmd = [OCAML_INFERENCE_PATH, board_hex]
        if model_path and os.path.exists(model_path):
            cmd.append(model_path)
        
        # Call OCaml inference
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=5.0
        )
        
        if result.returncode == 0:
            output = json.loads(result.stdout)
            return output['move'], output['time_ms'], output.get('node_budget', 1000)
        else:
            print(f"OCaml inference error: {result.stderr}")
            return None, None, None
            
    except Exception as e:
        print(f"Error calling OCaml backend: {e}")
        return None, None, None

# --- Routes ---

@app.route('/')
def index():
    # Check if models directory exists and list available models
    models = []
    if os.path.exists(MODELS_DIR):
        models = [f for f in os.listdir(MODELS_DIR) if f.endswith('.json')]
    
    # Check if OCaml backend is available
    ocaml_available = os.path.exists(OCAML_INFERENCE_PATH)
    
    return render_template('index.html', models=models, ocaml_available=ocaml_available)

@app.route('/api/models', methods=['GET'])
def get_models():
    """Return list of available models"""
    models = []
    if os.path.exists(MODELS_DIR):
        models = [f for f in os.listdir(MODELS_DIR) if f.endswith('.json')]
    return jsonify(models)

@app.route('/api/get_move', methods=['POST'])
def api_get_move():
    """REST endpoint for getting AI move"""
    try:
        data = request.get_json()
        board = data.get('board', [])
        model_name = data.get('model', '')
        
        # Convert board to int representation
        board_int = 0
        for i in range(4):
            for j in range(4):
                if board[i][j] > 0:
                    board_int |= (int(board[i][j]).bit_length() & 0xF) << ((i * 4 + j) * 4)
        
        # Get move from OCaml backend
        model_path = os.path.join(MODELS_DIR, model_name) if model_name else None
        move, inference_time, node_budget = get_ocaml_move(board_int, model_path)
        
        return jsonify({
            'move': move,
            'inference_time': inference_time,
            'node_budget': node_budget,
            'success': True
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/experiment_results')
def get_experiment_results():
    """Return experiment results for display"""
    return jsonify(EXPERIMENT_RESULTS)

# --- Socket handlers ---

@socketio.on('connect')
def handle_connect():
    print('Client connected')
    emit('connected', {'data': 'Connected to GP 2048 server'})

@socketio.on('disconnect')
def handle_disconnect():
    print('Client disconnected')

@socketio.on('start_training')
def handle_start_training(data):
    """Start training with given parameters"""
    global training_thread, stop_training_event
    
    # Reset the stop event
    stop_training_event.clear()
    
    # Extract parameters
    params = {
        'generations': int(data.get('generations', 50)),
        'population_size': int(data.get('population_size', 100)),
        'tournament_size': int(data.get('tournament_size', 5)),
        'mutation_prob': float(data.get('mutation_prob', 0.2)),
        'crossover_prob': float(data.get('crossover_prob', 0.8)),
        'max_depth': int(data.get('max_depth', 5)),
        'evaluation_games': int(data.get('evaluation_games', 5)),
        'search_depth': int(data.get('search_depth', 2))
    }
    
    # Run training in a separate thread
    def train_worker():
        try:
            run_training(params, request.sid)
        except Exception as e:
            print(f"Training error: {e}")
            socketio.emit('training_update', {'log': f"Error: {str(e)}"}, to=request.sid)
    
    training_thread = threading.Thread(target=train_worker)
    training_thread.start()

@socketio.on('stop_training')
def handle_stop_training():
    """Stop the current training session"""
    global stop_training_event
    stop_training_event.set()
    emit('training_update', {'log': 'Stopping training...'})

def run_training(params, sid):
    """Run the genetic programming training"""
    engine = GPEngine(
        population_size=params['population_size'],
        generations=params['generations'],
        tournament_size=params['tournament_size'],
        mutation_prob=params['mutation_prob'],
        crossover_prob=params['crossover_prob'],
        max_depth=params['max_depth'],
        games_per_individual=params['evaluation_games'],
        fitness_search_depth=params['search_depth']
    )
    
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
        eval_args = [(p, engine.games_per_individual, engine.fitness_search_depth) for p in engine.population]
        results = list(engine.pool.imap(evaluate_fitness_worker, eval_args))
        engine.population = results
        
        engine.population.sort(key=lambda p: p.fitness, reverse=True)
        best_program = engine.population[0]
        avg_fitness = sum(p.fitness for p in engine.population) / engine.population_size
        avg_game_score = sum(p.game_score for p in engine.population) / engine.population_size
        
        # Prepare stats for frontend
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

        # Create the next generation
        next_generation = []
        if engine.elitism_size > 0:
            next_generation.extend(engine.population[:engine.elitism_size])

        while len(next_generation) < engine.population_size:
            if stop_training_event.is_set():
                break
            
            parent1 = engine._tournament_selection()
            if random.random() < engine.crossover_prob:
                parent2 = engine._tournament_selection()
                offspring = engine._crossover(parent1, parent2)
            else:
                offspring = parent1.copy()
            
            if random.random() < engine.mutation_prob:
                offspring = engine._mutate(offspring)
            
            next_generation.append(offspring)
        
        engine.population = next_generation

    # Save the best program
    if not stop_training_event.is_set():
        best_program = max(engine.population, key=lambda p: p.fitness)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        model_filename = f'best_gen{engine.generations}_{timestamp}.json'
        model_path = os.path.join(MODELS_DIR, model_filename)
        
        with open(model_path, 'w') as f:
            f.write(serialize_program(best_program))
        
        socketio.emit('training_finished', {
            'log': f"Training complete! Best fitness: {best_program.fitness:.2f}",
            'new_model': model_filename
        }, to=sid)
    
    engine.pool.close()
    engine.pool.join()

@socketio.on('request_new_game')
def handle_new_game():
    """Start a new game"""
    board = Game2048.reset_board()
    emit('new_game_state', {
        'board': str(board),
        'score': 0,
        'max_tile': Game2048.get_max_tile(board),
        'is_over': False
    })

@app.route('/api/play_complete_game', methods=['POST'])
def play_complete_game():
    """Get complete game trace from OCaml backend"""
    try:
        data = request.get_json()
        model_name = data.get('model', '')
        seed = data.get('seed', 42)
        
        # Build command
        cmd = [OCAML_INFERENCE_PATH, '--play-game']
        if model_name:
            model_path = os.path.join(MODELS_DIR, model_name)
            if os.path.exists(model_path):
                cmd.append(model_path)
        cmd.append(str(seed))
        
        # Call OCaml to play complete game
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10.0
        )
        
        if result.returncode == 0:
            game_data = json.loads(result.stdout)
            return jsonify({
                'success': True,
                'trace': game_data['trace'],
                'final_score': game_data['final_score'],
                'max_tile': game_data['max_tile'],
                'total_moves': game_data['total_moves'],
                'time_ms': game_data['time_ms'],
                'node_budget': game_data['node_budget']
            })
        else:
            return jsonify({
                'success': False,
                'error': result.stderr or 'Failed to play game'
            }), 500
            
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@socketio.on('request_complete_game')
def handle_complete_game(data):
    """Play a complete game and return the trace for replay"""
    try:
        model_name = data.get('model', '')
        seed = data.get('seed', random.randint(1, 100000))
        
        # Build command
        cmd = [OCAML_INFERENCE_PATH, '--play-game']
        if model_name:
            model_path = os.path.join(MODELS_DIR, model_name)
            if os.path.exists(model_path):
                cmd.append(model_path)
        cmd.append(str(seed))
        
        # Call OCaml to play complete game
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10.0
        )
        
        if result.returncode == 0:
            game_data = json.loads(result.stdout)
            emit('complete_game_result', {
                'success': True,
                'trace': game_data['trace'],
                'final_score': game_data['final_score'],
                'max_tile': game_data['max_tile'],
                'total_moves': game_data['total_moves'],
                'time_ms': game_data['time_ms'],
                'node_budget': game_data['node_budget']
            })
        else:
            emit('complete_game_result', {
                'success': False,
                'error': result.stderr or 'Failed to play game'
            })
            
    except Exception as e:
        emit('complete_game_result', {
            'success': False,
            'error': str(e)
        })

@socketio.on('request_next_move')
def handle_next_move(data):
    """
    Given a board state, calculate and return the best move using OCaml backend.
    """
    try:
        board_int = int(data['board'])
        model_name = data.get('model')
        
        # Build path to model file
        model_path = None
        if model_name and model_name != 'default':
            model_path = os.path.join(MODELS_DIR, model_name)
        
        # Use OCaml backend for fast inference
        move_idx, time_ms, node_budget = get_ocaml_move(board_int, model_path)
        
        if move_idx is not None and move_idx != -1:
            move_fns = {
                0: Game2048.move_up, 1: Game2048.move_down,
                2: Game2048.move_left, 3: Game2048.move_right
            }
            
            # Execute the move
            new_board, score_gain, _ = move_fns[move_idx](board_int)
            new_board_with_tile = Game2048.add_random_tile(new_board)
            is_over = Game2048.is_game_over(new_board_with_tile)
            max_tile = Game2048.get_max_tile(new_board_with_tile)
            
            emit('next_move_result', {
                'move': move_idx,
                'score_gain': score_gain,
                'new_board': str(new_board_with_tile),
                'is_over': is_over,
                'max_tile': max_tile,
                'inference_time_ms': time_ms,
                'node_budget': node_budget
            })
        else:
            # No valid moves or error
            emit('next_move_result', {'move': -1, 'is_over': True})
            
    except Exception as e:
        print(f"Error in next move handler: {e}")
        emit('next_move_result', {'error': str(e)})

if __name__ == '__main__':
    # Build OCaml inference if not available
    if not os.path.exists(OCAML_INFERENCE_PATH):
        print("Building OCaml inference CLI...")
        os.system("cd .. && dune build inference_cli.exe")
    
    socketio.run(app, debug=True, port=5050, allow_unsafe_werkzeug=True)
