#!/usr/bin/env python
"""Test the web interface using Selenium"""

import time
import sys
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException

def test_web_interface():
    print("Starting web interface test...")
    
    # Setup Chrome options
    options = webdriver.ChromeOptions()
    options.add_argument('--headless')  # Run in headless mode
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    
    try:
        # Create driver
        driver = webdriver.Chrome(options=options)
        driver.set_window_size(1280, 800)
        
        # Navigate to the app
        print("Navigating to http://localhost:5050...")
        driver.get("http://localhost:5050")
        
        # Wait for page to load
        wait = WebDriverWait(driver, 10)
        new_game_btn = wait.until(EC.presence_of_element_located((By.ID, "new-game-btn")))
        print("✓ Page loaded successfully")
        
        # Test 1: Start a new game
        print("Testing new game...")
        new_game_btn.click()
        time.sleep(0.5)
        
        # Check if board is rendered
        tiles = driver.find_elements(By.CLASS_NAME, "tile")
        print(f"✓ Board rendered with {len(tiles)} tiles")
        
        # Test 2: Check if AI play button is enabled
        ai_play_btn = driver.find_element(By.ID, "ai-play-btn")
        
        if ai_play_btn.is_enabled():
            print("✓ AI Play button is enabled (OCaml backend available)")
            
            # Test 3: Let AI make a few moves
            print("Testing AI moves...")
            ai_play_btn.click()
            
            # Wait for AI to make moves
            inference_time_found = False
            for i in range(10):
                time.sleep(0.2)
                
                # Check inference time
                inference_time_el = driver.find_element(By.ID, "inference-time")
                inference_time = inference_time_el.text
                
                if inference_time != "-":
                    inference_time_found = True
                    print(f"✓ AI move {i+1}: Inference time = {inference_time} ms")
                
                # Check score and max tile
                score = driver.find_element(By.ID, "game-score").text
                max_tile = driver.find_element(By.ID, "game-max-tile").text
                print(f"  Score: {score}, Max tile: {max_tile}")
                
                # Stop after a few moves to keep test quick
                if i >= 5:
                    break
            
            if inference_time_found:
                print("✓ OCaml inference times displayed correctly")
            else:
                print("✗ No inference times found - OCaml backend may not be working")
            
            # Stop AI
            try:
                ai_stop_btn = driver.find_element(By.ID, "ai-stop-btn")
                if ai_stop_btn.is_displayed():
                    ai_stop_btn.click()
            except:
                pass
                
        else:
            print("✗ AI Play button is disabled - OCaml backend not available")
            return False
        
        print("\n✅ All tests passed!")
        return True
        
    except TimeoutException:
        print("❌ Test failed: Page failed to load")
        return False
    except Exception as e:
        print(f"❌ Test failed: {str(e)}")
        return False
    finally:
        driver.quit()

if __name__ == "__main__":
    # Check if server is running
    import requests
    try:
        response = requests.get("http://localhost:5050", timeout=2)
    except:
        print("Error: Flask server is not running on http://localhost:5050")
        print("Please run: cd python && python app.py")
        sys.exit(1)
    
    # Run test
    success = test_web_interface()
    sys.exit(0 if success else 1)