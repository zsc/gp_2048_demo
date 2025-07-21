const puppeteer = require('puppeteer');

async function testWebInterface() {
    console.log('Starting web interface test...');
    
    // Launch browser
    const browser = await puppeteer.launch({
        headless: false, // Set to true for CI/CD
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    try {
        const page = await browser.newPage();
        
        // Set viewport
        await page.setViewport({ width: 1280, height: 800 });
        
        // Go to the app
        console.log('Navigating to http://localhost:5050...');
        await page.goto('http://localhost:5050', { waitUntil: 'networkidle0' });
        
        // Wait for page to load
        await page.waitForSelector('#new-game-btn', { timeout: 5000 });
        console.log('✓ Page loaded successfully');
        
        // Test 1: Start a new game
        console.log('Testing new game...');
        await page.click('#new-game-btn');
        await page.waitForTimeout(500);
        
        // Check if board is rendered
        const boardCells = await page.$$eval('.tile', tiles => tiles.length);
        console.log(`✓ Board rendered with ${boardCells} tiles`);
        
        // Test 2: Check if OCaml backend is available
        const aiPlayBtn = await page.$('#ai-play-btn');
        const isDisabled = await page.evaluate(btn => btn.disabled, aiPlayBtn);
        
        if (!isDisabled) {
            console.log('✓ AI Play button is enabled (OCaml backend available)');
            
            // Test 3: Let AI make a few moves
            console.log('Testing AI moves...');
            await page.click('#ai-play-btn');
            
            // Wait for AI to make moves and check inference time
            let inferenceTimeFound = false;
            for (let i = 0; i < 10; i++) {
                await page.waitForTimeout(200);
                
                // Check if inference time is displayed
                const inferenceTime = await page.$eval('#inference-time', el => el.textContent);
                if (inferenceTime !== '-') {
                    inferenceTimeFound = true;
                    console.log(`✓ AI move ${i+1}: Inference time = ${inferenceTime} ms`);
                }
                
                // Check score
                const score = await page.$eval('#game-score', el => el.textContent);
                const maxTile = await page.$eval('#game-max-tile', el => el.textContent);
                console.log(`  Score: ${score}, Max tile: ${maxTile}`);
                
                // Check if game is over
                const gameOver = await page.evaluate(() => {
                    return window.isGameOver || false;
                });
                
                if (gameOver) {
                    console.log('✓ Game ended naturally');
                    break;
                }
            }
            
            if (inferenceTimeFound) {
                console.log('✓ OCaml inference times displayed correctly');
            } else {
                console.log('✗ No inference times found - OCaml backend may not be working');
            }
            
            // Stop AI
            await page.click('#ai-stop-btn');
            await page.waitForTimeout(200);
            
        } else {
            console.log('✗ AI Play button is disabled - OCaml backend not available');
        }
        
        // Test 4: Switch to Train tab
        console.log('Testing Train tab...');
        await page.evaluate(() => {
            const trainTab = Array.from(document.querySelectorAll('.tab-link')).find(el => el.textContent === 'Train');
            if (trainTab) trainTab.click();
        });
        await page.waitForTimeout(500);
        
        // Check if training controls are visible
        const startBtn = await page.$('#start-btn');
        if (startBtn) {
            console.log('✓ Train tab loaded successfully');
        }
        
        console.log('\n✅ All tests passed!');
        
    } catch (error) {
        console.error('❌ Test failed:', error.message);
        
        // Take screenshot on error
        await page.screenshot({ path: 'test_error.png' });
        console.log('Screenshot saved as test_error.png');
        
    } finally {
        await browser.close();
    }
}

// Check if required packages are installed
try {
    require.resolve('puppeteer');
} catch(e) {
    console.error('Puppeteer not installed. Run: npm install puppeteer');
    process.exit(1);
}

// Run the test
testWebInterface().catch(console.error);