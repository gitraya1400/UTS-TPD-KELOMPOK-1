# OLAP Analysis Notebook - Panduan Penggunaan

## Ringkasan
File `OLAP_ANALYSIS.ipynb` adalah Jupyter Notebook komprehensif untuk analisis OLAP pada data Livestock Intelligence. Notebook ini mengimplementasikan semua 5 analisis utama dari laporan praktikum Anda.

---

## Struktur Notebook

### SECTION 1: Setup & Database Connection
- Import semua libraries yang diperlukan (pandas, plotly, scipy, etc.)
- Koneksi ke PostgreSQL database
- Load fact table dan dimensional tables

**Persiapan**: Pastikan `.env` file sudah dikonfigurasi dengan:
```
DB_HOST=localhost
DB_PORT=5432
DB_NAME=datawarehouse_db
DB_USER=postgres
DB_PASSWORD=your_password
```

---

### SECTION 2: OLAP Operations
Demonstrasi operasi OLAP dasar:
- **SLICING**: Filter single dimension (misal: hanya Sapi, hanya JAWA TIMUR)
- **DICING**: Filter multiple dimensions sekaligus
- **ROLL-UP**: Agregasi ke level lebih tinggi (dari bulan ke tahun)
- **DRILL-DOWN**: Disagregasi ke level lebih rendah (dari tahun ke bulan)

**Output**: Data samples dan counts untuk validasi

---

### SECTION 3: ANALYSIS 1 - Early Warning System
**Tujuan**: Identifikasi wilayah risiko tinggi untuk intervensi dini

**Komponen**:
1. Top 10 provinsi dengan risk index tertinggi
2. Timeline trend untuk 5 provinsi risiko tertinggi
3. Current alert status (latest month) dengan color coding:
   - 🔴 CRITICAL (≥0.7)
   - 🟠 WARNING (0.5-0.7)
   - 🟡 CAUTION (0.3-0.5)
   - 🟢 SAFE (<0.3)

**Visualisasi**: 
- Bar chart horizontal untuk top risiko
- Interactive line chart untuk timeline

---

### SECTION 4: ANALYSIS 2 - Tren Harga vs Wabah
**Tujuan**: Buktikan apakah volatilitas harga disebabkan oleh wabah atau faktor lain

**Metodologi**:
- Hitung Pearson correlation antara avg_harga dan sum_jumlah_sakit
- P-value test untuk signifikansi
- Interpretasi otomatis:
  - r ≥ 0.7: KUAT → "Kenaikan harga sangat terkait wabah"
  - r 0.5-0.7: SEDANG → "Cukup terkait"
  - r < 0.5: LEMAH → "Kemungkinan faktor lain dominan"

**Visualisasi**:
- Dual-axis time series (harga + jumlah sakit)
- Scatter plot dengan regression line untuk setiap komoditas

---

### SECTION 5: ANALYSIS 3 - Supply vs Demand Gap
**Tujuan**: Ukur ketimpangan antara ketersediaan dan kebutuhan

**Dua Level**:

**Level Logistik** (satuan Ekor):
- Mutasi (sum_vol_mutasi) vs Permintaan (avg_permintaan_bulanan)
- Output: Gap dalam ekor + persentase

**Level Konsumsi** (satuan Kg):
- Karkas (sum_realisasi_karkas) vs Konsumsi (avg_konsumsi_bulanan)
- Output: Gap dalam kg + persentase

**Status**:
- ✓ SURPLUS: supply > demand
- ✗ DEFICIT: supply < demand

**Analisis Lanjutan**:
- Summary statistics per komoditas
- Deficit analysis per provinsi
- Timeline visualization

---

### SECTION 6: ANALYSIS 4 - Peta Risiko Spasial
**Tujuan**: Identifikasi "titik lemah" logistik berdasarkan populasi & kesehatan

**Klasifikasi Zona**:
```
RED ZONE (Prioritas Utama):
  - Supply Risk Index ≥ 0.5 AND Disease Density di atas 75th percentile

ORANGE ZONE (Perhatian):
  - Supply Risk Index ≥ 0.5 OR Disease Density di atas median

GREEN ZONE (Stabil):
  - Di bawah threshold
```

**Metrik**:
- Disease Density = (Jumlah Sakit / Populasi Ternak) × 1000
- Populasi Ternak = Average populasi di wilayah

**Output**:
- Spatial risk matrix (tabel)
- Bubble chart (populasi vs disease vs risk)
- Prioritas alokasi vaksinasi/intervensi

---

### SECTION 7: ANALYSIS 5 - Ketergantungan Supply
**Tujuan**: Identifikasi "provinsi kunci" yang dominan supply nasional

**Analisis**:
- Supply Concentration: % kontribusi setiap provinsi terhadap pasokan nasional
- Cumulative percentage (Pareto analysis)
- Identifikasi "critical suppliers" (supply > 10% AND risk > 0.5)

**Output**:
- Supply concentration table dengan cumulative %
- Pareto chart untuk visualisasi
- Critical vulnerability alert:
  - Daftar provinsi yang supply besar tapi risiko tinggi
  - Rekomendasi backup supply planning

---

## Cara Menggunakan Notebook

### 1. Setup Awal
```bash
# Masuk ke direktori project
cd /vercel/share/v0-project

# Install dependencies (jika belum)
pip install jupyter pandas plotly scipy matplotlib seaborn psycopg2 sqlalchemy python-dotenv

# Launch Jupyter
jupyter notebook OLAP_ANALYSIS.ipynb
```

### 2. Konfigurasi Database
Sebelum menjalankan cell pertama, pastikan:
- Database PostgreSQL sudah running
- Data Warehouse sudah ter-load dengan fact table & dimensions
- File `.env` ada di direktori yang sama dengan notebook (atau parent directory)

### 3. Eksekusi Sel
Run cells secara berurutan (top-to-bottom):
- **Green cells** = Mandatory (setup, loading, core analysis)
- **Blue cells** = Optional (alternative views atau deeper analysis)

### 4. Modifikasi untuk Kebutuhan Spesifik
Notebook dirancang modular, Anda bisa:
- Ubah commodities filter: `olap_cube[olap_cube['nama_komoditas'] == 'Sapi']`
- Ubah tahun range: `olap_cube[olap_cube['tahun'].isin([2023, 2024])
- Ubah provinces: `olap_cube[olap_cube['nama_provinsi'].isin(['JAWA TIMUR', 'JAWA BARAT'])
- Ubah threshold risk: `olap_cube[olap_cube['supply_risk_index'] >= 0.6]`

---

## Output yang Dihasilkan

### Tabel (Pandas DataFrame)
- Risk assessments per province
- Supply-demand gaps
- Correlation statistics
- Spatial risk matrices
- Concentration indices

### Visualisasi (Interactive Plotly)
- Line charts (time series)
- Bar charts (comparisons)
- Bubble charts (3D analysis)
- Scatter plots (correlations)
- Pareto charts

### Statistik & Insights
- Pearson correlation coefficients
- Risk classifications
- Deficit/Surplus identification
- Vulnerability assessments
- Policy recommendations

---

## Contoh Penggunaan

### Scenario 1: Monitor Provinsi Spesifik
```python
# Di cell manapun, tambahkan:
target_prov = 'JAWA TIMUR'
prov_data = olap_cube[olap_cube['nama_provinsi'] == target_prov]
print(prov_data[['tahun', 'bulan', 'supply_risk_index', 'avg_harga']].tail(12))
```

### Scenario 2: Analisis Komoditas Tertentu
```python
sapi_data = olap_cube[olap_cube['nama_komoditas'] == 'Sapi']
sapi_data.groupby('tahun')['supply_risk_index'].agg(['mean', 'min', 'max'])
```

### Scenario 3: Deep Dive ke Period Tertentu
```python
# Crisis month analysis
crisis_period = olap_cube[(olap_cube['tahun'] == 2024) & (olap_cube['bulan'] >= 10)]
crisis_period.groupby('nama_provinsi')['supply_risk_index'].mean().nlargest(5)
```

---

## Troubleshooting

### Error: "Failed to connect to database"
- ✓ Cek DB_PASSWORD di .env file (jangan ada space/special char yang tidak di-escape)
- ✓ Cek PostgreSQL running: `pg_isready -h localhost -p 5432`
- ✓ Verify table exists: `psql -U postgres -d datawarehouse_db -c "\dt"`

### Error: "Table not found"
- ✓ Pastikan ETL sudah completed di file: CODE/LOAD/ETL_Load_Kelompok1.py
- ✓ Query table directly: `SELECT COUNT(*) FROM fact_supply_resilience;`

### Visualisasi tidak tampil
- ✓ Jika offline, gunakan renderer: `plotly.io.show(fig, renderer='notebook')`
- ✓ Pastikan Plotly terinstall: `pip install plotly --upgrade`

### Performa slow
- ✓ Tambah filter periode: `olap_cube[olap_cube['tahun'] >= 2023]`
- ✓ Gunakan `.sample()` untuk preview: `olap_cube.sample(1000)`

---

## Notes Penting

1. **Data Freshness**: Notebook membaca langsung dari live database. Untuk reproducibility, catat waktu eksekusi.

2. **Statistical Rigor**: Semua correlation tests menggunakan Pearson dengan p-value validation. Hanya hubungan dengan p < 0.05 dianggap significant.

3. **OLAP Aggregations**: Semua agregasi dilakukan di database (PySpark) bukan di memory, untuk scalability.

4. **Export Results**: Untuk export hasil ke format lain:
   ```python
   # Export to CSV
   risk_by_prov.to_csv('risk_assessment.csv')
   
   # Export to Excel
   with pd.ExcelWriter('analysis_results.xlsx') as writer:
       risk_by_prov.to_excel(writer, sheet_name='Risk Assessment')
       gap_logistik.to_excel(writer, sheet_name='Supply Gap')
   ```

---

## Next Steps

Setelah menjalankan notebook ini:
1. **Validate findings** dengan domain experts (Dinas Pertanian, iSIKHNAS operators)
2. **Deep-dive analysis** untuk specific problem areas yang teridentifikasi
3. **Schedule automated reports** menggunakan Apache Airflow (ada di CODE/EXTRACT)
4. **Integrate dengan Shiny dashboard** untuk real-time monitoring (ada di R_SHINY_APP/)

---

**Version**: 1.0  
**Last Updated**: 2025  
**Status**: Ready for Production Analysis
