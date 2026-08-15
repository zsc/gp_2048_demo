`timescale 1ns/1ps

module game2048_tournament_queue #(
  parameter integer GAME_COUNT = 128,
  parameter integer ACTIVE_GAME_COUNT = 128,
  parameter integer SEARCH_ENGINES = 4,
  parameter integer WORKERS_PER_ENGINE = 16,
  parameter integer NODE_BUDGET = 1000,
  parameter integer REPLAY_GAMES = 4,
  parameter integer MAX_REPLAY_RECORDS = 4096,
  parameter logic [31:0] BASE_SEED = 32'h2048_c0de,
  parameter integer SUMMARY_PAGE_ADDRESS_WIDTH =
      $clog2((GAME_COUNT + 3) / 4),
  parameter integer REPLAY_GAME_ADDRESS_WIDTH = $clog2(REPLAY_GAMES),
  parameter integer REPLAY_PAGE_ADDRESS_WIDTH =
      $clog2(MAX_REPLAY_RECORDS / 4)
) (
  input  logic                              clock,
  input  logic                              reset,
  input  logic [SUMMARY_PAGE_ADDRESS_WIDTH-1:0] summary_page_address_i,
  output logic [511:0]                      summary_page_data_o,
  input  logic [REPLAY_GAME_ADDRESS_WIDTH-1:0] replay_game_address_i,
  input  logic [REPLAY_PAGE_ADDRESS_WIDTH-1:0] replay_page_address_i,
  output logic [511:0]                      replay_page_data_o,
  output logic                              busy_o,
  output logic                              done_o,
  output logic [$clog2(GAME_COUNT+1)-1:0]   completed_count_o,
  output logic [$clog2(GAME_COUNT+1)-1:0]   win_count_o,
  output logic [63:0]                       total_moves_o,
  output logic [63:0]                       total_search_cycles_o,
  output logic [63:0]                       wall_cycles_o,
  output logic [SEARCH_ENGINES-1:0]         engine_busy_o,
  output logic [3:0]                        state_o
);
  import game2048_pkg::*;

  // Only ACTIVE_GAME_COUNT games have live mutable state.  Completed slots are
  // recycled onto the next global game id, so large tournaments grow summary
  // BRAM rather than duplicating all context registers.
  localparam integer GAME_ID_WIDTH = $clog2(GAME_COUNT);
  localparam integer SLOT_ID_WIDTH = $clog2(ACTIVE_GAME_COUNT);
  localparam integer ENGINE_ID_WIDTH = $clog2(SEARCH_ENGINES);
  localparam integer REPLAY_COUNT_WIDTH = $clog2(MAX_REPLAY_RECORDS + 1);
  localparam integer REPLAY_RECORD_ADDRESS_WIDTH =
      $clog2(REPLAY_GAMES * MAX_REPLAY_RECORDS);
  localparam integer REPLAY_PAGES = MAX_REPLAY_RECORDS / 4;
  localparam integer TOTAL_REPLAY_PAGES = REPLAY_GAMES * REPLAY_PAGES;
  localparam integer REPLAY_PAGE_INDEX_WIDTH = $clog2(TOTAL_REPLAY_PAGES);
  localparam integer SUMMARY_PAGES = (GAME_COUNT + 3) / 4;

  localparam logic [3:0] ST_INIT_TILE    = 4'd0;
  localparam logic [3:0] ST_INIT_CELL    = 4'd1;
  localparam logic [3:0] ST_INIT_SPAWN   = 4'd2;
  localparam logic [3:0] ST_COLLECT      = 4'd3;
  localparam logic [3:0] ST_RESULT       = 4'd4;
  localparam logic [3:0] ST_RANDOM_TILE  = 4'd5;
  localparam logic [3:0] ST_RANDOM_CELL  = 4'd6;
  localparam logic [3:0] ST_COMMIT_MOVE  = 4'd7;
  localparam logic [3:0] ST_DONE         = 4'd8;

  logic [63:0] game_board [0:ACTIVE_GAME_COUNT-1];
  logic [31:0] game_random [0:ACTIVE_GAME_COUNT-1];
  logic [15:0] game_moves [0:ACTIVE_GAME_COUNT-1];
  logic [3:0] game_highest [0:ACTIVE_GAME_COUNT-1];
  logic game_won [0:ACTIVE_GAME_COUNT-1];
  logic game_done [0:ACTIVE_GAME_COUNT-1];
  logic game_over [0:ACTIVE_GAME_COUNT-1];
  logic game_overflow [0:ACTIVE_GAME_COUNT-1];
  logic game_invalid [0:ACTIVE_GAME_COUNT-1];
  logic game_replay_truncated [0:ACTIVE_GAME_COUNT-1];
  logic [GAME_ID_WIDTH-1:0] game_global_id [0:ACTIVE_GAME_COUNT-1];
  logic [REPLAY_COUNT_WIDTH-1:0] game_replay_count [0:REPLAY_GAMES-1];

  logic [SLOT_ID_WIDTH-1:0] ready_fifo [0:ACTIVE_GAME_COUNT-1];
  logic [SLOT_ID_WIDTH-1:0] ready_read_pointer;
  logic [SLOT_ID_WIDTH-1:0] ready_write_pointer;
  logic [SLOT_ID_WIDTH:0] ready_count;

  logic engine_start [0:SEARCH_ENGINES-1];
  logic engine_busy [0:SEARCH_ENGINES-1];
  logic engine_done [0:SEARCH_ENGINES-1];
  logic [63:0] engine_board [0:SEARCH_ENGINES-1];
  logic [SLOT_ID_WIDTH-1:0] engine_game [0:SEARCH_ENGINES-1];
  logic [2:0] engine_move [0:SEARCH_ENGINES-1];
  logic [63:0] engine_cycles [0:SEARCH_ENGINES-1];
  logic [63:0] engine_calls [0:SEARCH_ENGINES-1];
  logic [63:0] engine_expanded [0:SEARCH_ENGINES-1];
  logic [63:0] engine_cutoffs [0:SEARCH_ENGINES-1];
  logic engine_overflow [0:SEARCH_ENGINES-1];
  logic engine_pending [0:SEARCH_ENGINES-1];
  logic [ENGINE_ID_WIDTH-1:0] dispatch_engine;
  logic [ENGINE_ID_WIDTH-1:0] collect_engine;

  generate
    genvar engine_gen;
    for (engine_gen = 0; engine_gen < SEARCH_ENGINES;
         engine_gen = engine_gen + 1) begin : engines
      search_accel #(.WORKERS(WORKERS_PER_ENGINE)) u_search (
        .clock(clock),
        .reset(reset),
        .start(engine_start[engine_gen]),
        .board_i(engine_board[engine_gen]),
        .budget_i(NODE_BUDGET[15:0]),
        .busy(engine_busy[engine_gen]),
        .done(engine_done[engine_gen]),
        .move_o(engine_move[engine_gen]),
        .cycles_o(engine_cycles[engine_gen]),
        .calls_o(engine_calls[engine_gen]),
        .expanded_o(engine_expanded[engine_gen]),
        .cutoffs_o(engine_cutoffs[engine_gen]),
        .overflow_o(engine_overflow[engine_gen])
      );
      always_comb engine_busy_o[engine_gen] = engine_busy[engine_gen];
    end
  endgenerate

  (* ram_style = "block" *) logic [127:0] replay_bank_0 [0:TOTAL_REPLAY_PAGES-1];
  (* ram_style = "block" *) logic [127:0] replay_bank_1 [0:TOTAL_REPLAY_PAGES-1];
  (* ram_style = "block" *) logic [127:0] replay_bank_2 [0:TOTAL_REPLAY_PAGES-1];
  (* ram_style = "block" *) logic [127:0] replay_bank_3 [0:TOTAL_REPLAY_PAGES-1];
  logic replay_write_enable;
  logic [REPLAY_RECORD_ADDRESS_WIDTH-1:0] replay_write_index;
  logic [127:0] replay_write_data;
  logic [REPLAY_PAGE_INDEX_WIDTH-1:0] replay_read_page_index;

  // A game writes one compact record when it finishes.  Four narrow banks
  // provide a complete 512-bit JTAG page without fanning the read mux into
  // every live game-context field.
  (* ram_style = "block" *) logic [127:0] summary_bank_0 [0:SUMMARY_PAGES-1];
  (* ram_style = "block" *) logic [127:0] summary_bank_1 [0:SUMMARY_PAGES-1];
  (* ram_style = "block" *) logic [127:0] summary_bank_2 [0:SUMMARY_PAGES-1];
  (* ram_style = "block" *) logic [127:0] summary_bank_3 [0:SUMMARY_PAGES-1];
  logic summary_write_enable;
  logic [GAME_ID_WIDTH-1:0] summary_write_game;
  logic [127:0] summary_write_data;

  always_comb begin
    replay_read_page_index =
        (replay_game_address_i * REPLAY_PAGES) + replay_page_address_i;
  end

  always_ff @(posedge clock) begin
    replay_page_data_o <= {
      replay_bank_3[replay_read_page_index],
      replay_bank_2[replay_read_page_index],
      replay_bank_1[replay_read_page_index],
      replay_bank_0[replay_read_page_index]
    };
    if (replay_write_enable) begin
      case (replay_write_index[1:0])
        2'd0: replay_bank_0[replay_write_index[
            REPLAY_RECORD_ADDRESS_WIDTH-1:2]] <= replay_write_data;
        2'd1: replay_bank_1[replay_write_index[
            REPLAY_RECORD_ADDRESS_WIDTH-1:2]] <= replay_write_data;
        2'd2: replay_bank_2[replay_write_index[
            REPLAY_RECORD_ADDRESS_WIDTH-1:2]] <= replay_write_data;
        default: replay_bank_3[replay_write_index[
            REPLAY_RECORD_ADDRESS_WIDTH-1:2]] <= replay_write_data;
      endcase
    end
  end

  always_ff @(posedge clock) begin
    summary_page_data_o <= {
      summary_bank_3[summary_page_address_i],
      summary_bank_2[summary_page_address_i],
      summary_bank_1[summary_page_address_i],
      summary_bank_0[summary_page_address_i]
    };
    if (summary_write_enable) begin
      case (summary_write_game[1:0])
        2'd0: summary_bank_0[summary_write_game[GAME_ID_WIDTH-1:2]] <=
            summary_write_data;
        2'd1: summary_bank_1[summary_write_game[GAME_ID_WIDTH-1:2]] <=
            summary_write_data;
        2'd2: summary_bank_2[summary_write_game[GAME_ID_WIDTH-1:2]] <=
            summary_write_data;
        default: summary_bank_3[summary_write_game[GAME_ID_WIDTH-1:2]] <=
            summary_write_data;
      endcase
    end
  end

  logic [SLOT_ID_WIDTH-1:0] initialization_game;
  logic [GAME_ID_WIDTH-1:0] initialization_global_game;
  logic [GAME_ID_WIDTH:0] next_global_game;
  logic initialization_second_tile;
  logic initialization_recycled_slot;
  logic [SLOT_ID_WIDTH-1:0] processor_game;
  logic [63:0] processor_board;
  logic [31:0] processor_random;
  logic [2:0] processor_move;
  logic [31:0] processor_search_cycles;
  logic processor_engine_overflow;
  logic [1:0] spawn_value;
  logic [4:0] spawn_cell;

  logic [31:0] random_next;
  logic [3:0] random_candidate;
  logic [4:0] processor_empty_count;
  logic [4:0] processor_random_limit;
  logic [3:0] processor_empty_rank;
  logic [4:0] processor_selected_cell;
  logic [63:0] processor_spawned_board;
  logic [3:0] processor_spawned_highest;

  always_comb begin
    random_next = lfsr_next32(processor_random);
    random_candidate = random_next[3:0];
    processor_empty_count = count_empty(processor_board);
    processor_random_limit = random_rejection_limit(processor_empty_count);
    processor_empty_rank = accepted_empty_rank(
        random_candidate, processor_empty_count);
    processor_selected_cell = select_empty_by_rank(
        processor_board, processor_empty_rank);
    processor_spawned_board = set_spawn(
        processor_board, spawn_cell[3:0], spawn_value);
    processor_spawned_highest = highest_tile_exponent(
        processor_spawned_board);
  end

  function automatic logic [31:0] seed_for_game(
      input logic [GAME_ID_WIDTH-1:0] game_id
  );
    logic [31:0] seed;
    begin
      seed = BASE_SEED ^ (32'h9e37_79b9 * game_id);
      seed_for_game = seed == 32'd0 ? 32'h1 : seed;
    end
  endfunction

  always_ff @(posedge clock) begin : queue_controller
    integer engine_index;
    logic do_enqueue;
    logic do_dequeue;
    logic [SLOT_ID_WIDTH-1:0] enqueue_game;
    logic [SLOT_ID_WIDTH-1:0] dequeue_game;
    logic [GAME_ID_WIDTH-1:0] terminal_global_game;
    logic [63:0] moved_board;
    logic terminal_is_win;
    logic terminal_game_over;
    logic terminal_invalid;
    logic [63:0] terminal_meta;

    do_enqueue = 1'b0;
    do_dequeue = 1'b0;
    enqueue_game = '0;
    dequeue_game = ready_fifo[ready_read_pointer];

    replay_write_enable <= 1'b0;
    summary_write_enable <= 1'b0;
    for (engine_index = 0; engine_index < SEARCH_ENGINES;
         engine_index = engine_index + 1) begin
      engine_start[engine_index] <= 1'b0;
    end

    if (reset) begin
      state_o <= ST_INIT_TILE;
      busy_o <= 1'b1;
      done_o <= 1'b0;
      completed_count_o <= '0;
      win_count_o <= '0;
      total_moves_o <= 64'd0;
      total_search_cycles_o <= 64'd0;
      wall_cycles_o <= 64'd0;
      ready_read_pointer <= '0;
      ready_write_pointer <= '0;
      ready_count <= '0;
      dispatch_engine <= '0;
      collect_engine <= '0;
      initialization_game <= '0;
      initialization_global_game <= '0;
      next_global_game <= ACTIVE_GAME_COUNT;
      initialization_second_tile <= 1'b0;
      initialization_recycled_slot <= 1'b0;
      processor_game <= '0;
      processor_board <= 64'd0;
      processor_random <= seed_for_game('0);
      processor_move <= 3'd7;
      processor_search_cycles <= 32'd0;
      processor_engine_overflow <= 1'b0;
      spawn_value <= 2'd0;
      spawn_cell <= 5'd31;
      replay_write_index <= '0;
      replay_write_data <= 128'd0;
      summary_write_game <= '0;
      summary_write_data <= 128'd0;
      for (engine_index = 0; engine_index < SEARCH_ENGINES;
           engine_index = engine_index + 1)
        engine_pending[engine_index] <= 1'b0;
    end else begin
      if (!done_o)
        wall_cycles_o <= wall_cycles_o + 64'd1;

      for (engine_index = 0; engine_index < SEARCH_ENGINES;
           engine_index = engine_index + 1) begin
        if (engine_done[engine_index])
          engine_pending[engine_index] <= 1'b1;
      end

      // Dispatch at most one ready game per cycle.  A game leaves the FIFO
      // before it enters an engine and is re-enqueued only after its spawn.
      if ((ready_count != 0) &&
          !engine_busy[dispatch_engine] &&
          !engine_start[dispatch_engine] &&
          !engine_done[dispatch_engine] &&
          !engine_pending[dispatch_engine]) begin
        engine_board[dispatch_engine] <= game_board[dequeue_game];
        engine_game[dispatch_engine] <= dequeue_game;
        engine_start[dispatch_engine] <= 1'b1;
        do_dequeue = 1'b1;
      end
      if (dispatch_engine == ENGINE_ID_WIDTH'(SEARCH_ENGINES - 1))
        dispatch_engine <= '0;
      else
        dispatch_engine <= dispatch_engine + 1'b1;

      case (state_o)
        ST_INIT_TILE: begin
          processor_random <= random_next;
          if (random_candidate < 4'd10) begin
            spawn_value <= random_candidate == 4'd0 ? 2'd2 : 2'd1;
            state_o <= ST_INIT_CELL;
          end
        end

        ST_INIT_CELL: begin
          processor_random <= random_next;
          if ({1'b0, random_candidate} < processor_random_limit) begin
            spawn_cell <= processor_selected_cell;
            state_o <= ST_INIT_SPAWN;
          end
        end

        ST_INIT_SPAWN: begin
          if (!initialization_second_tile) begin
            processor_board <= processor_spawned_board;
            initialization_second_tile <= 1'b1;
            state_o <= ST_INIT_TILE;
          end else begin
            game_board[initialization_game] <= processor_spawned_board;
            game_random[initialization_game] <= processor_random;
            game_moves[initialization_game] <= 16'd0;
            game_highest[initialization_game] <=
                highest_tile_exponent(processor_spawned_board);
            game_won[initialization_game] <= 1'b0;
            game_done[initialization_game] <= 1'b0;
            game_over[initialization_game] <= 1'b0;
            game_overflow[initialization_game] <= 1'b0;
            game_invalid[initialization_game] <= 1'b0;
            game_replay_truncated[initialization_game] <= 1'b0;
            game_global_id[initialization_game] <= initialization_global_game;
            if (initialization_global_game < REPLAY_GAMES) begin
              game_replay_count[initialization_global_game[
                  REPLAY_GAME_ADDRESS_WIDTH-1:0]] <=
                  REPLAY_COUNT_WIDTH'(1);
              replay_write_enable <= 1'b1;
              replay_write_index <=
                  initialization_global_game * MAX_REPLAY_RECORDS;
              replay_write_data <= {
                {22'd0, 32'd0, 2'd0, 5'd31, 3'd7},
                processor_spawned_board
              };
            end
            do_enqueue = 1'b1;
            enqueue_game = initialization_game;
            if (initialization_recycled_slot) begin
              initialization_recycled_slot <= 1'b0;
              state_o <= ST_COLLECT;
            end else if (initialization_game ==
                SLOT_ID_WIDTH'(ACTIVE_GAME_COUNT - 1)) begin
              state_o <= ST_COLLECT;
            end else begin
              initialization_game <= initialization_game + 1'b1;
              initialization_global_game <= initialization_global_game + 1'b1;
              processor_board <= 64'd0;
              processor_random <= seed_for_game(
                  initialization_global_game + 1'b1);
              initialization_second_tile <= 1'b0;
              state_o <= ST_INIT_TILE;
            end
          end
        end

        ST_COLLECT: begin
          if (engine_pending[collect_engine]) begin
            processor_game <= engine_game[collect_engine];
            processor_move <= engine_move[collect_engine];
            processor_search_cycles <= engine_cycles[collect_engine][31:0];
            processor_engine_overflow <= engine_overflow[collect_engine];
            engine_pending[collect_engine] <= 1'b0;
            state_o <= ST_RESULT;
          end else if (collect_engine ==
                       ENGINE_ID_WIDTH'(SEARCH_ENGINES - 1)) begin
            collect_engine <= '0;
          end else begin
            collect_engine <= collect_engine + 1'b1;
          end
        end

        ST_RESULT: begin
          terminal_global_game = game_global_id[processor_game];
          total_search_cycles_o <= total_search_cycles_o +
              processor_search_cycles;
          game_overflow[processor_game] <=
              game_overflow[processor_game] | processor_engine_overflow;
          moved_board = move_dir(
              game_board[processor_game], processor_move[1:0]);
          if ((processor_move == 3'd7) ||
              (moved_board == game_board[processor_game])) begin
            terminal_is_win = game_won[processor_game] ||
                (game_highest[processor_game] >= 4'd11);
            terminal_game_over = board_game_over(game_board[processor_game]);
            terminal_invalid = (processor_move != 3'd7) ||
                !terminal_game_over;
            game_done[processor_game] <= 1'b1;
            game_over[processor_game] <= terminal_game_over;
            if (terminal_invalid)
              game_invalid[processor_game] <= 1'b1;

            terminal_meta = 64'd0;
            terminal_meta[15:0] = game_moves[processor_game];
            terminal_meta[19:16] = game_highest[processor_game];
            terminal_meta[20] = terminal_is_win;
            terminal_meta[21] = terminal_game_over;
            terminal_meta[22] = game_overflow[processor_game] |
                processor_engine_overflow;
            terminal_meta[23] = game_invalid[processor_game] |
                terminal_invalid;
            terminal_meta[24] = game_replay_truncated[processor_game];
            terminal_meta[25] = 1'b1;
            if (terminal_global_game < REPLAY_GAMES)
              terminal_meta[38:26] = 13'(
                  game_replay_count[terminal_global_game[
                      REPLAY_GAME_ADDRESS_WIDTH-1:0]]);
            summary_write_enable <= 1'b1;
            summary_write_game <= terminal_global_game;
            summary_write_data <= {
              terminal_meta, game_board[processor_game]
            };

            completed_count_o <= completed_count_o + 1'b1;
            if (terminal_is_win)
              win_count_o <= win_count_o + 1'b1;
            if (completed_count_o == GAME_COUNT - 1) begin
              done_o <= 1'b1;
              busy_o <= 1'b0;
              state_o <= ST_DONE;
            end else begin
              if (next_global_game < GAME_COUNT) begin
                initialization_game <= processor_game;
                initialization_global_game <=
                    next_global_game[GAME_ID_WIDTH-1:0];
                next_global_game <= next_global_game + 1'b1;
                processor_board <= 64'd0;
                processor_random <= seed_for_game(
                    next_global_game[GAME_ID_WIDTH-1:0]);
                initialization_second_tile <= 1'b0;
                initialization_recycled_slot <= 1'b1;
                state_o <= ST_INIT_TILE;
              end else begin
                state_o <= ST_COLLECT;
              end
            end
          end else begin
            processor_board <= moved_board;
            processor_random <= game_random[processor_game];
            state_o <= ST_RANDOM_TILE;
          end
        end

        ST_RANDOM_TILE: begin
          processor_random <= random_next;
          if (random_candidate < 4'd10) begin
            spawn_value <= random_candidate == 4'd0 ? 2'd2 : 2'd1;
            state_o <= ST_RANDOM_CELL;
          end
        end

        ST_RANDOM_CELL: begin
          processor_random <= random_next;
          if ({1'b0, random_candidate} < processor_random_limit) begin
            spawn_cell <= processor_selected_cell;
            state_o <= ST_COMMIT_MOVE;
          end
        end

        ST_COMMIT_MOVE: begin
          game_board[processor_game] <= processor_spawned_board;
          game_random[processor_game] <= processor_random;
          game_moves[processor_game] <= game_moves[processor_game] + 1'b1;
          if (processor_spawned_highest > game_highest[processor_game])
            game_highest[processor_game] <= processor_spawned_highest;
          if (processor_spawned_highest >= 4'd11)
            game_won[processor_game] <= 1'b1;
          total_moves_o <= total_moves_o + 64'd1;

          if (game_global_id[processor_game] < REPLAY_GAMES) begin
            if (game_replay_count[game_global_id[processor_game][
                REPLAY_GAME_ADDRESS_WIDTH-1:0]] < MAX_REPLAY_RECORDS) begin
              replay_write_enable <= 1'b1;
              replay_write_index <=
                  (game_global_id[processor_game] * MAX_REPLAY_RECORDS) +
                  game_replay_count[game_global_id[processor_game][
                      REPLAY_GAME_ADDRESS_WIDTH-1:0]];
              replay_write_data <= {
                {
                  22'(game_replay_count[game_global_id[processor_game][
                      REPLAY_GAME_ADDRESS_WIDTH-1:0]]),
                  processor_search_cycles,
                  spawn_value,
                  spawn_cell,
                  processor_move
                },
                processor_spawned_board
              };
              game_replay_count[game_global_id[processor_game][
                  REPLAY_GAME_ADDRESS_WIDTH-1:0]] <=
                  game_replay_count[game_global_id[processor_game][
                      REPLAY_GAME_ADDRESS_WIDTH-1:0]] + 1'b1;
            end else begin
              game_replay_truncated[processor_game] <= 1'b1;
            end
          end

          do_enqueue = 1'b1;
          enqueue_game = processor_game;
          state_o <= ST_COLLECT;
        end

        default: begin
          done_o <= 1'b1;
          busy_o <= 1'b0;
          state_o <= ST_DONE;
        end
      endcase

      if (do_enqueue) begin
        ready_fifo[ready_write_pointer] <= enqueue_game;
        ready_write_pointer <= ready_write_pointer + 1'b1;
      end
      if (do_dequeue)
        ready_read_pointer <= ready_read_pointer + 1'b1;
      case ({do_enqueue, do_dequeue})
        2'b10: ready_count <= ready_count + 1'b1;
        2'b01: ready_count <= ready_count - 1'b1;
        default: ready_count <= ready_count;
      endcase
    end
  end

  wire unused_metrics = ^engine_calls[0] ^ ^engine_expanded[0] ^
      ^engine_cutoffs[0];
endmodule
