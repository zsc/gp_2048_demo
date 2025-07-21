# Manual Test Instructions

## 1. Start the Flask App
```bash
cd python
python app.py
```

## 2. Open Browser
Navigate to: http://localhost:5050

## 3. Test Steps
1. Click "Play by AI" button
2. Select a model from dropdown (e.g., "simple_fast.json")
3. Click "Start AI Game"
4. Watch the AI play automatically
5. Check that:
   - Moves are being made
   - OCaml inference time is displayed
   - Node budget is shown
   - Game progresses smoothly

## 4. Available Models
- simple_fast.json: Fast with 500 node budget
- balanced_best.json: Balanced with 5000 node budget  
- high_performance.json: Performance with 1000 node budget

## 5. Expected Results
- AI should make reasonable moves
- Inference time should be displayed in milliseconds
- Node budget should match the model's configuration
- Game should reach reasonable scores (3000-10000+)