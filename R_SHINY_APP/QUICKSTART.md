# 🚀 Quick Start Guide - Livestock Intelligence Dashboard

## ⏱️ 5 Minutes to Dashboard

### 1️⃣ Clone & Navigate (30 seconds)

```bash
cd R_SHINY_APP
```

### 2️⃣ Install Packages (2 minutes)
*First time only*

```bash
Rscript install_packages.R
```

**Expected Output:**
```
✓ shiny installed successfully
✓ shinydashboard installed successfully
✓ RPostgres installed successfully
...
✓ All dependencies installed successfully!
```

### 3️⃣ Configure Database (1 minute)

```bash
# Copy template
cp .env.example .env

# Edit with your database credentials
# nano .env  (or use your favorite editor)
```

**Required settings in .env:**
```
DB_HOST=your.postgres.server
DB_PORT=5432
DB_NAME=datawarehouse_db
DB_USER=your_username
DB_PASSWORD=your_password
```

### 4️⃣ Place Shapefile (30 seconds)

```bash
mkdir -p data
# Copy ADMINISTRAS_PROVINSI.shp* files to data/ directory
cp ADMINISTRAS_PROVINSI.shp* data/
```

### 5️⃣ Launch! (1 minute)

```bash
# Option A: From R console
Rscript -e "shiny::runApp()"

# Option B: In RStudio
# Open app.R → Click "Run App" button
```

**Dashboard running at:** `http://localhost:3838`

---

## 🎯 First Actions in Dashboard

### 🔴 Red Pill (Deep Dive)
1. Go to **"Executive Summary"** tab
2. Look for **red alert boxes** - these are critical situations
3. Check **"Top 5 Provinsi dengan Risiko Tertinggi"** chart
4. Click on **choropleth map** - hover over provinces for details

### 🟡 Orange Pill (Analysis)
1. Switch to **"Analisis Sektor Riil"** tab
2. See **Supply vs Demand Gap** charts
3. Check **"Ketergantungan Supply"** - which provinces supply > 60%?
4. Read the alert box at bottom

### 🟢 Green Pill (Investigation)
1. Go to **"Investigasi & Korelasi"** tab
2. Look at **dual-axis time series** (price vs disease)
3. Check **correlation coefficient** - is harga connected to penyakit?
4. Scroll down for detailed data table

---

## 🎛️ Using Filters

### Basic Filter Workflow
```
1. Sidebar → Adjust filters
   - Provinsi: Choose "Nasional" or specific province
   - Komoditas: Select "Sapi" or "Ayam"
   - Tahun: Slide to year range you want
   - Bulan: Check which months to include

2. Click "Apply Filters" button

3. ALL charts update automatically ✨
```

### Example: High-Risk Sapi Analysis
```
Provinsi: Nasional           ← See all provinces
Komoditas: Sapi              ← Only beef cattle
Tahun: 2024-2025            ← Recent data only
Bulan: [1,3,5,7,9,11]       ← Every other month
→ Click "Apply Filters"
```

### Example: Deep Dive into Jawa Timur
```
Provinsi: Jawa Timur        ← Single province
Komoditas: Sapi             ← Beef only
Tahun: 2023-2025            ← Recent 3 years
Bulan: [1-12]               ← All months
→ Click "Apply Filters"
→ Go to Tab 3 for time series
```

---

## 📊 Understanding the Tabs

### Tab 1: "Executive Summary (The Alarm)"
**What to look for:**
- 🔴 **Red Risk Index** = Emergency situation
- 📍 **Map colors** = Visual risk assessment by region
- 📊 **Top 5 table** = Which provinces need immediate action

**Action triggers:**
- If you see red box at bottom = High dependency + risk crisis
- Map shows red region = Check that province's trend

---

### Tab 2: "Analisis Sektor Riil"
**What to look for:**
- 📉 **Red gap (below 0)** = Not enough supply for demand
- 📈 **Green gap (above 0)** = More supply than needed
- 🎯 **> 60% in treemap** = Over-concentration risk

**Action triggers:**
- If red gap = Alert stakeholders about shortage
- If > 60% concentrated = Diversify supply sources

---

### Tab 3: "Investigasi & Korelasi"
**What to look for:**
- 📈 **Lines move together** = Price-disease correlation exists
- 📊 **Correlation number** = Strength of relationship
- 📋 **Interpretation text** = Whether this is supply failure or market speculation

**Example interpretation:**
```
r = 0.82 "KUAT POSITIF"
→ Harga tinggi KETIKA penyakit banyak
→ Ini adalah supply failure (good diagnosis!)
→ Perlu intervensi di kesehatan hewan
```

---

## ❓ Common Questions

### Q: Where do I see which province is in danger?
**A:** Tab 1 "Executive Summary" → Look for red colors in:
1. KPI boxes (red = danger level)
2. Top 5 chart (ordered by risk)
3. Choropleth map (red regions = high risk)

### Q: How do I know if it's disease or market speculation?
**A:** Tab 3 "Investigasi & Korelasi"
- r > 0.7 = Disease causing price spike (supply failure)
- r < 0.3 = Something else (speculation, seasonal, etc)

### Q: What does "Ketergantungan" mean?
**A:** How much one province supplies the whole country
- > 60% = TOO HIGH (DANGEROUS)
- 20-40% = Balanced
- < 20% = Good (diversified)

### Q: Why is the map empty?
**A:** Shapefile might not be in right location
- Check: `data/ADMINISTRAS_PROVINSI.shp` exists
- If missing: App still works, just no map visualization

### Q: Data looks old, how do I refresh?
**A:** Data comes from PostgreSQL database
- To update: Load new ETL data to database
- Then: Restart Shiny app
- Or: Re-apply filters to force query

---

## 🔧 Troubleshooting (30 seconds)

### Problem: App won't start
```
Error: "Database connection failed"

Solution:
1. Check .env file exists and is readable
2. Verify DB_HOST, DB_USER, DB_PASSWORD
3. Test: psql -h DB_HOST -U DB_USER -d DB_NAME
4. Check PostgreSQL is running
```

### Problem: Map is missing
```
Warning: "Shapefile not found"

Solution:
1. Check: ls data/ADMINISTRAS_PROVINSI.shp
2. If missing: cp ADMINISTRAS_PROVINSI.shp* data/
3. Restart app - other features still work
```

### Problem: Charts show "No data"
```
Possible causes:
1. Filters too restrictive
   → Try "Nasional" instead of specific province
   → Increase year range
   → Select more months

2. Wrong province/komoditas name
   → Check exact spelling in database
   → Try clicking dropdown instead of typing

3. No data for that combination
   → Add more months/years to filter
   → Switch to different commodity
```

### Problem: App is slow
```
Solution (try in order):
1. Reduce date range in filters (e.g., 2024-2025 only)
2. Select specific province (not "Nasional")
3. Check database indexes:
   → SELECT * FROM pg_indexes WHERE tablename = 'fact_supply_resilience';
4. Check database resources:
   → SELECT count(*) FROM fact_supply_resilience;
```

---

## 📚 Next Steps

### Learn More
- 📖 Read `README.md` for full feature list
- 🔧 Check `TECHNICAL.md` for how it works
- 🚀 See `DEPLOYMENT.md` for server setup

### Customize
- Colors: Edit `color_risk_palette()` in global.R
- Thresholds: Update risk ranges in server.R
- Add charts: Copy/modify existing renderPlotly() blocks
- Change alerts: Edit alert trigger logic in server.R

### Deploy
- Local: Ready to use now!
- Server: Follow `DEPLOYMENT.md` Linux section
- Docker: Use Dockerfile from `DEPLOYMENT.md`
- Cloud (AWS): Check `DEPLOYMENT.md` EC2 section

---

## 💡 Pro Tips

### 1. Keyboard Shortcut (in RStudio)
```
Open app.R → Cmd/Ctrl + Enter → Auto-runs app
```

### 2. Speed Up Development
```r
# Test single query fast
con <- dbConnect(RPostgres::Postgres(), ...)
test <- dbGetQuery(con, "SELECT * FROM dim_prov LIMIT 5")
head(test)
```

### 3. Debug a Chart
```r
# Add to server.R temporarily
print(str(filtered_data()))  # See structure
print(head(filtered_data()))  # See first rows
```

### 4. Export Data
- Click **"Download Data"** button in sidebar
- Exports filtered dataset as CSV
- Perfect for further analysis in Excel

### 5. Share Dashboard
1. Deploy with HTTPS (see DEPLOYMENT.md)
2. Share URL: `https://your-domain.com`
3. Users can adjust filters without tech knowledge

---

## 🎓 Learning Path

### Day 1: Exploration
- [ ] Launch dashboard
- [ ] Click through all 3 tabs
- [ ] Try different filters
- [ ] Read the alert messages

### Day 2: Understanding Data
- [ ] Check top risk provinces
- [ ] Look at supply gaps for Jabodetabek
- [ ] Find correlations between price & disease
- [ ] Understand your data patterns

### Day 3: Analysis
- [ ] Identify critical dependencies
- [ ] Compare Sapi vs Ayam trends
- [ ] Track seasonal patterns
- [ ] Make action decisions

### Week 2: Sharing
- [ ] Deploy to team server
- [ ] Train stakeholders
- [ ] Collect feedback
- [ ] Plan improvements

---

## 📞 Quick Reference

### Database Queries (for testing)

```sql
-- See available provinces
SELECT DISTINCT nama_provinsi FROM dim_prov ORDER BY nama_provinsi;

-- Check recent data
SELECT COUNT(*) FROM fact_supply_resilience WHERE tahun = 2025;

-- View risk statistics
SELECT 
  MIN(supply_risk_index) as min_risk,
  MAX(supply_risk_index) as max_risk,
  AVG(supply_risk_index) as avg_risk
FROM fact_supply_resilience;
```

### R Commands (for debugging)

```r
# Check connection
dbIsValid(con)  # TRUE = good, FALSE = bad

# List available tables
dbListTables(con)

# Quick test query
dbGetQuery(con, "SELECT COUNT(*) as row_count FROM fact_supply_resilience")

# Stop app (in RStudio console)
# Press Esc or Ctrl+C
```

### File Locations

```bash
# Config
~/.Rprofile              # User R startup (if exists)
./R_SHINY_APP/.env       # Database credentials (SECRET!)

# Logs (if deployed to server)
/var/log/shiny-server/access.log
/var/log/postgresql/postgresql.log

# App code
./R_SHINY_APP/app.R      # Entry point
./R_SHINY_APP/global.R   # Database & setup
./R_SHINY_APP/ui.R       # Layout
./R_SHINY_APP/server.R   # Logic

# Data
./R_SHINY_APP/data/ADMINISTRAS_PROVINSI.shp*  # Shapefile (required)
```

---

## ✨ Success Indicators

You'll know it's working when you see:

✅ Dashboard loads in browser without errors  
✅ All 3 tabs display with data  
✅ Filters update charts when you change them  
✅ Choropleth map shows colored provinces  
✅ Correlation value shows as decimal  
✅ Alerts appear when conditions met  
✅ Charts are interactive (hover, zoom, etc)  

---

## 🎉 You're Ready!

Your Livestock Intelligence Dashboard is ready to use. Start exploring your data and make informed decisions about livestock supply resilience!

**Questions?** Check README.md, TECHNICAL.md, or DEPLOYMENT.md  
**Issues?** Review Troubleshooting section above  
**Need help?** Check the inline code comments in global.R/server.R

---

**Happy analyzing! 📊📈**

---

**Version**: 1.0  
**Last Updated**: 2026-05-04  
**Status**: ✅ Ready for Use
