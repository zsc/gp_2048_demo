#!/usr/bin/env python
"""Complete web app test using Selenium to verify AI game plays to completion"""

import subprocess
import time
import os
import sys
from datetime import datetime

def install_selenium():
    """Install selenium if not available"""
    try:
        import selenium
    except ImportError:
        print("Installing selenium...")
        subprocess.run([sys.executable, "-m", "pip", "install", "selenium"], check=True)

def test_complete_ai_game():
    """Test the complete AI game flow in browser"""
    
    # Import after ensuring installation
    from selenium import webdriver
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait, Select
    from selenium.webdriver.support import expected_conditions as EC
    from selenium.common.exceptions import TimeoutException, NoAlertPresentException
    
    # Start Flask app
    print("Starting Flask app...")
    app_process = subprocess.Popen(
        ["python", "app.py"],
        cwd="python",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    
    # Give it time to start
    time.sleep(3)
    
    # Setup Chrome options
    options = webdriver.ChromeOptions()
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    # Uncomment for headless mode
    # options.add_argument('--headless')
    
    driver = None
    try:
        print("Starting Chrome browser...")
        driver = webdriver.Chrome(options=options)
        driver.set_window_size(1200, 800)
        
        # Navigate to app
        print("Navigating to http://localhost:5050...")
        driver.get("http://localhost:5050")
        
        # Wait for page to load and game board
        wait = WebDriverWait(driver, 10)
        try:
            board_container = wait.until(EC.presence_of_element_located((By.ID, "board-container")))
            print("Page loaded successfully, found game board")
        except TimeoutException:
            print("ERROR: Could not find board-container")
            driver.save_screenshot("test_no_board.png")
            raise
        
        # Try to refresh models (button might not be visible/needed)
        try:
            print("Looking for refresh button...")
            refresh_btn = wait.until(EC.element_to_be_clickable((By.ID, "refresh-models-btn")))
            refresh_btn.click()
            time.sleep(1)
            print("Model list refreshed")
        except TimeoutException:
            print("Refresh button not found/clickable, skipping...")
        
        # Select a model using JavaScript to avoid visibility issues
        print("Selecting model...")
        try:
            # Wait for model selector
            model_select_element = wait.until(EC.presence_of_element_located((By.ID, "model-selector")))
            
            # Get options using JavaScript
            options = driver.execute_script("""
                var select = document.getElementById('model-selector');
                var options = [];
                for (var i = 0; i < select.options.length; i++) {
                    options.push(select.options[i].value);
                }
                return options;
            """)
            print(f"Available models: {options}")
            
            # Select model using JavaScript
            if "simple_fast.json" in options:
                driver.execute_script("""
                    var select = document.getElementById('model-selector');
                    select.value = 'simple_fast.json';
                    select.dispatchEvent(new Event('change', { bubbles: true }));
                """)
                print("Selected: simple_fast.json")
            else:
                print("WARNING: simple_fast.json not found")
                if len(options) > 1:
                    driver.execute_script("""
                        var select = document.getElementById('model-selector');
                        select.selectedIndex = 1;
                        select.dispatchEvent(new Event('change', { bubbles: true }));
                    """)
                    print(f"Selected first available model: {options[1] if len(options) > 1 else 'none'}")
        except Exception as e:
            print(f"Error selecting model: {e}")
            driver.save_screenshot("test_model_error.png")
        
        time.sleep(0.5)
        
        # Take screenshot of initial state
        driver.save_screenshot("test_0_initial_state.png")
        
        # Wait a bit for socket connection to establish
        print("Waiting for socket connection...")
        time.sleep(2)
        
        # First click New Game to initialize board
        print("Clicking 'New Game' to initialize board...")
        new_game_btn = driver.find_element(By.ID, "new-game-btn")
        new_game_btn.click()
        
        # Wait for board to have tiles
        print("Waiting for board to initialize...")
        time.sleep(3)
        
        # Check board state using JavaScript
        board_state = driver.execute_script("""
            return {
                boardInt: window.currentBoardInt ? window.currentBoardInt.toString() : 'undefined',
                score: window.currentScore,
                isGameOver: window.isGameOver,
                tiles: document.querySelectorAll('.tile').length,
                gameScore: document.getElementById('game-score').textContent,
                maxTile: document.getElementById('game-max-tile').textContent
            };
        """)
        print(f"Board state after New Game: {board_state}")
        
        # Check if board has tiles by looking for tile elements
        tiles = driver.find_elements(By.CLASS_NAME, "tile")
        if tiles:
            print(f"Board initialized with {len(tiles)} tiles")
            driver.save_screenshot("test_1_board_initialized.png")
        else:
            print("WARNING: Board appears empty after New Game")
            driver.save_screenshot("test_1_empty_board.png")
        
        # Get initial state
        initial_score = driver.find_element(By.ID, "game-score").text
        print(f"Initial score: {initial_score}")
        
        # Set playback speed to 20ms for faster testing
        print("Setting playback speed to 20ms...")
        driver.execute_script("""
            var slider = document.getElementById('playback-speed');
            slider.value = 20;
            slider.dispatchEvent(new Event('input', { bubbles: true }));
        """)
        
        # Now AI Play button should be enabled
        print("\nClicking 'Let AI Play' button...")
        ai_play_btn = wait.until(EC.element_to_be_clickable((By.ID, "ai-play-btn")))
        driver.save_screenshot("test_2_before_ai_play.png")
        ai_play_btn.click()
        
        # Monitor game progress
        print("Game started! Monitoring progress...")
        start_time = time.time()
        last_score = initial_score
        move_count = 0
        score_changes = []
        
        # Wait for game to complete (max 2 minutes)
        game_completed = False
        for i in range(120):  # 120 seconds max
            time.sleep(1)
            
            # Get current state
            current_score = driver.find_element(By.ID, "game-score").text
            max_tile = driver.find_element(By.ID, "game-max-tile").text
            inference_time = driver.find_element(By.ID, "inference-time").text
            node_budget = driver.find_element(By.ID, "node-budget").text
            
            # Check if score changed
            if current_score != last_score:
                move_count += 1
                score_changes.append((i, current_score))
                if move_count % 10 == 0:
                    print(f"  [{i:3d}s] Move {move_count}: Score={current_score}, MaxTile={max_tile}")
                last_score = current_score
            
            # Check if Stop button is visible (game still running)
            try:
                stop_btn = driver.find_element(By.ID, "ai-stop-btn")
                if not stop_btn.is_displayed():
                    # Game might be finished
                    time.sleep(2)  # Wait a bit more to be sure
                    break
            except:
                pass
            
            # Check for game over alert
            try:
                alert = driver.switch_to.alert
                alert_text = alert.text
                print(f"\nGame Over Alert: {alert_text}")
                # Take screenshot before accepting alert
                driver.save_screenshot("test_3_game_completed_with_alert.png")
                alert.accept()
                game_completed = True
                break
            except NoAlertPresentException:
                pass
        
        # Get final state
        final_score = driver.find_element(By.ID, "game-score").text
        final_max_tile = driver.find_element(By.ID, "game-max-tile").text
        final_inference_time = driver.find_element(By.ID, "inference-time").text
        final_node_budget = driver.find_element(By.ID, "node-budget").text
        
        # Take final screenshot after alert is dismissed
        driver.save_screenshot("test_4_final_state.png")
        
        # Calculate statistics
        total_time = time.time() - start_time
        
        # Print results
        print("\n" + "="*60)
        print("GAME COMPLETED!")
        print("="*60)
        print(f"Total time: {total_time:.1f} seconds")
        print(f"Total moves: {move_count}")
        print(f"Final score: {final_score}")
        print(f"Max tile achieved: {final_max_tile}")
        print(f"OCaml inference time: {final_inference_time}ms")
        print(f"Node budget used: {final_node_budget}")
        
        if score_changes:
            print(f"\nScore progression:")
            for i, (time_point, score) in enumerate(score_changes[:5]):
                print(f"  Move {i+1} at {time_point}s: {score}")
            if len(score_changes) > 10:
                print(f"  ... ({len(score_changes)-10} more moves)")
            for i, (time_point, score) in enumerate(score_changes[-5:]):
                print(f"  Move {len(score_changes)-5+i+1} at {time_point}s: {score}")
        
        # Verify game completed properly
        success = game_completed and int(final_score) > 0 and move_count > 20
        
        print(f"\nTest Result: {'PASSED' if success else 'FAILED'}")
        if not success:
            if not game_completed:
                print("  - Game did not complete with alert")
            if int(final_score) == 0:
                print("  - Final score is 0")
            if move_count <= 20:
                print(f"  - Too few moves: {move_count}")
        
        return success
        
    except Exception as e:
        print(f"\nError during test: {e}")
        
        # Check if it's an alert
        game_completed = False
        try:
            alert = driver.switch_to.alert
            alert_text = alert.text
            print(f"Alert present: {alert_text}")
            driver.save_screenshot("test_error_with_alert.png")
            alert.accept()
            game_completed = True
            
            # Get final state after alert
            time.sleep(1)
            final_score = driver.find_element(By.ID, "game-score").text
            final_max_tile = driver.find_element(By.ID, "game-max-tile").text
            driver.save_screenshot("test_4_final_state_after_alert.png")
            
            print(f"\nGame completed successfully!")
            print(f"Final score: {final_score}, Max tile: {final_max_tile}")
            
            # Extract score from alert text
            import re
            score_match = re.search(r'score: (\d+)', alert_text, re.IGNORECASE)
            if score_match:
                alert_score = int(score_match.group(1))
                return alert_score > 1000  # Success if score > 1000
                
        except NoAlertPresentException:
            pass
        
        if not game_completed:
            import traceback
            traceback.print_exc()
            
            # Try to take error screenshot
            if driver:
                try:
                    driver.save_screenshot("test_error.png")
                    print("Error screenshot saved as test_error.png")
                except:
                    pass
        
        return game_completed
        
    finally:
        # Cleanup
        if driver:
            driver.quit()
        app_process.terminate()
        app_process.wait()
        print("\nCleanup completed.")

if __name__ == "__main__":
    print("=== Complete AI Game Web Test ===")
    print(f"Time: {datetime.now()}\n")
    
    # Install selenium if needed
    install_selenium()
    
    # Run test
    success = test_complete_ai_game()
    
    if success:
        print("\n✅ Web app test PASSED! AI game plays to completion.")
    else:
        print("\n❌ Web app test FAILED! Please check the implementation.")
    
    # Cleanup test files
    for f in ["test_direct_flow.py", "test_full_web_flow.py"]:
        if os.path.exists(f):
            os.remove(f)
    
    sys.exit(0 if success else 1)