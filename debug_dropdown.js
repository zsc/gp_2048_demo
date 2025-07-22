const puppeteer = require('puppeteer');

(async () => {
    const browser = await puppeteer.launch({ headless: false });
    const page = await browser.newPage();
    
    // Listen to console events
    page.on('console', msg => console.log('Console:', msg.text()));
    page.on('error', msg => console.log('Error:', msg));
    page.on('pageerror', error => console.log('Page error:', error.message));
    
    // Navigate to the page
    await page.goto('http://localhost:5050');
    
    // Wait a bit for the page to load
    await page.waitForTimeout(2000);
    
    // Check if the dropdown has options
    const options = await page.evaluate(() => {
        const selector = document.getElementById('model-selector');
        if (!selector) return 'No model-selector found';
        
        const options = Array.from(selector.options).map(opt => ({
            value: opt.value,
            text: opt.text
        }));
        return options;
    });
    
    console.log('Dropdown options:', JSON.stringify(options, null, 2));
    
    // Try to click refresh button
    try {
        await page.click('#refresh-models');
        await page.waitForTimeout(1000);
        
        const optionsAfter = await page.evaluate(() => {
            const selector = document.getElementById('model-selector');
            return Array.from(selector.options).map(opt => ({
                value: opt.value,
                text: opt.text
            }));
        });
        console.log('Options after refresh:', JSON.stringify(optionsAfter, null, 2));
    } catch (e) {
        console.log('Could not click refresh:', e.message);
    }
    
    // Keep browser open for inspection
    // await browser.close();
})();