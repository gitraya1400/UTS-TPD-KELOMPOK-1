import json

def create_notebook():
    nb = {
        "cells": [],
        "metadata": {
            "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
            "language_info": {"name": "python", "version": "3.10.0"}
        },
        "nbformat": 4,
        "nbformat_minor": 5
    }

    def md(src):
        nb["cells"].append({"cell_type": "markdown", "metadata": {}, "source": [line + '\n' for line in src.split('\n')]})

    def code(src):
        nb["cells"].append({"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": [line + '\n' for line in src.split('\n')]})

    md("""# ETL Pipeline: Livestock Intelligence - FASE 1 (EXTRACT)
**Laporan Praktikum Teknologi Perekayasaan Data - Kelompok 1 (3SI1)**

Sesuai dengan pedoman proyek, fase ini dikhususkan untuk **Extract** (menarik data dari berbagai sumber) tanpa melakukan transformasi seperti pembersihan atau imputasi (yang akan dilakukan di fase Transform).

**Sumber Data:**
1. **BPS**: Menggunakan Web API (Scraping) dan Dummy Data. Data akan di-load langsung ke tabel relasional di PostgreSQL (`bps_db`) yang bertindak sebagai Operational Data Store (Source Database).
2. **iSIKHNAS**: Menggunakan MySQL (`isikhnas_db`) yang telah diload via phpMyAdmin.
3. **PIHPS**: Menggunakan file Excel/CSV harian (`final_data.xlsx`).""")

    code("""# =========================================================
# 1. IMPORT LIBRARY DAN KONFIGURASI DATABASE
# =========================================================

import requests
import pandas as pd
import numpy as np
import random
import time
import os
from tqdm import tqdm
from sqlalchemy import create_engine, text

# Matikan warning untuk output yang bersih
import warnings
warnings.filterwarnings('ignore')
random.seed(42) # Untuk konsistensi dummy data

# --- KONEKSI POSTGRESQL (BPS_DB & STAGING_DB) ---
PG_USER = 'postgres'
PG_PASS = 'postgres'  # Sesuaikan dengan password lokal
PG_HOST = 'localhost'
PG_PORT = '5432'

# --- KONEKSI MYSQL (ISIKHNAS_DB) ---
MYSQL_USER = 'root'
MYSQL_PASS = ''       # Default XAMPP
MYSQL_HOST = 'localhost'
MYSQL_PORT = '3306'

# Inisialisasi Engine SQLAlchemy
engine_bps = create_engine(f'postgresql+psycopg2://{PG_USER}:{PG_PASS}@{PG_HOST}:{PG_PORT}/bps_db')
engine_staging = create_engine(f'postgresql+psycopg2://{PG_USER}:{PG_PASS}@{PG_HOST}:{PG_PORT}/staging_db')
engine_isikhnas = create_engine(f'mysql+pymysql://{MYSQL_USER}:{MYSQL_PASS}@{MYSQL_HOST}:{MYSQL_PORT}/isikhnas_db')

print("✅ Semua koneksi database telah diatur.")""")

    md("""---
## 1. EXTRACT DATA BPS (API SCRAPING & DUMMY)
Tahap ini akan mengekstrak data dari web API BPS. Sesuai instruksi, data produksi sapi dipindahkan ke *dummy* karena ketiadaan data yang komprehensif.

### 1.1 Persiapan Fungsi BPS API""")

    code("""# =========================================================
# 1.1 FUNGSI BPS API SCRAPING
# =========================================================

API_KEY = "d328d5f200379241367024848106698e"
YEARS = [2020, 2021, 2022, 2023, 2024, 2025]

# Definisi komoditas untuk di-scrape
COMMODITIES_TO_SCRAPE = [
    {
        "name": "Jumlah Penduduk",
        "type": "simdasi",
        "table_ids": ["WVRlTTcySlZDa3lUcFp6czNwbHl4QT09"],
        "keywords": ["jumlah", "penduduk"],
        "column_name": "jumlah_penduduk"
    },
    {
        "name": "Populasi Ternak - Sapi Potong (Ekor)",
        "type": "simdasi",
        "table_ids": ["S2ViU1dwVTlpSXRwU1MvendHN05Cdz09"],
        "keywords": ["populasi", "sapi", "potong"],
        "column_name": "populasi_sapi_potong"
    },
    {
        "name": "Populasi Unggas - Ayam Pedaging (Ekor)",
        "type": "simdasi",
        "table_ids": ["ckJyVXRMT05MWTNpaW9mdnVseFk0Zz09"],
        "keywords": ["populasi", "ayam", "pedaging"],
        "column_name": "populasi_ayam_pedaging"
    },
    {
        "name": "Produksi Daging Unggas - Ayam Pedaging (kg)",
        "type": "simdasi",
        "table_ids": ["dWhmNFl6WXYyR093R2NjTGM3NG9idz09"],
        "keywords": ["produksi", "daging", "ayam", "pedaging"],
        "column_name": "produksi_daging_ayam_pedaging"
    }
]

def get_bps_data(year, table_id, kode_wilayah="0000000"):
    url = f"https://webapi.bps.go.id/v1/api/interoperabilitas/datasource/simdasi/id/25/tahun/{year}/id_tabel/{table_id}/wilayah/{kode_wilayah}/key/{API_KEY}"
    try:
        response = requests.get(url, timeout=30)
        return response.json()
    except Exception as e:
        return None

def get_target_var_id(main_data, target_keywords):
    kolom_meta = main_data.get("kolom", {})
    for var_id, var_info in kolom_meta.items():
        nama_var = str(var_info.get("nama_variabel", "")).lower()
        if all(keyword in nama_var for keyword in target_keywords):
            return var_id
    return None

def parse_bps_simdasi_province_data(raw_data, year, nama_provinsi, target_keywords, value_column_name):
    rows = []
    if not raw_data or raw_data.get("status") != "OK":
        return pd.DataFrame()

    try:
        main_data = raw_data.get("data", [{}, {}])[1]
        target_var_id = get_target_var_id(main_data, target_keywords)

        if not target_var_id:
            return pd.DataFrame()

        for item in main_data.get("data", []):
            nama_wilayah = item.get("label", "")
            kode_wilayah = item.get("kode_wilayah", "")

            if nama_wilayah.lower() == nama_provinsi.lower():
                value = None
                if target_var_id in item.get("variables", {}):
                    value = item["variables"][target_var_id].get("value_raw", None)

                rows.append({
                    "tahun": year,
                    "provinsi": nama_provinsi,
                    "kode_wilayah": kode_wilayah,
                    value_column_name: value
                })
                break 
        return pd.DataFrame(rows)
    except Exception as e:
        return pd.DataFrame()""")

    md("""### 1.2 PRE-FLIGHT CHECK API BPS
Cell ini ditujukan khusus untuk memeriksa apakah tabel ID yang disediakan BPS masih aktif dan variabel target tersedia, sebelum scraping berjalan penuh. Anda bisa menghapus cell ini nantinya jika sudah yakin berjalan aman.""")

    code("""# =========================================================
# 1.2 PRE-FLIGHT CHECK (BISA DIHAPUS JIKA SUDAH AMAN)
# =========================================================
print("="*60)
print(" PRE-FLIGHT CHECK API BPS ")
print("="*60)

for commodity_info in COMMODITIES_TO_SCRAPE:
    commodity_name = commodity_info["name"]
    table_ids = commodity_info["table_ids"]
    keywords = commodity_info["keywords"]
    
    print(f"\\nMengecek: {commodity_name}")
    status_ok = False
    
    # Cek di tahun terbaru (2023)
    year_to_check = 2023 
    for tbl_id in table_ids:
        temp_data = get_bps_data(year_to_check, tbl_id, "0000000")
        if temp_data and temp_data.get("status") == "OK":
            main_data_check = temp_data.get("data", [{}, {}])[1]
            if get_target_var_id(main_data_check, keywords):
                print(f"  ✅ [SUKSES] Tabel ID {tbl_id} valid untuk tahun {year_to_check}.")
                status_ok = True
                break
    
    if not status_ok:
        print(f"  ❌ [GAGAL] Tidak dapat menemukan data yang valid untuk keyword {keywords}.")
        
print("\\nPre-flight check selesai.")""")

    md("""### 1.3 Eksekusi BPS Scraping""")

    code("""# =========================================================
# 1.3 EKSEKUSI SCRAPING API BPS
# =========================================================
print("🚀 Memulai proses scraping untuk semua komoditas...")

final_merged_df = pd.DataFrame()

for commodity_info in COMMODITIES_TO_SCRAPE:
    commodity_name = commodity_info["name"]
    commodity_keywords = commodity_info["keywords"]
    commodity_column_name = commodity_info["column_name"]

    print(f"\\n--- Mengambil data: {commodity_name} ---")
    commodity_dfs_for_all_years = [] 

    for year in YEARS:
        print(f"[{year}] Mencari data...")

        raw_data_for_year = None
        active_id = None 

        for tbl_id in commodity_info["table_ids"]:
            temp_data = get_bps_data(year, tbl_id, "0000000") 
            if temp_data and temp_data.get("status") == "OK":
                main_data_check = temp_data.get("data", [{}, {}])[1]
                if get_target_var_id(main_data_check, commodity_keywords):
                    active_id = tbl_id
                    raw_data_for_year = temp_data 
                    break
                    
        if not active_id:
            continue

        main_data_nasional = raw_data_for_year.get("data", [{}, {}])[1]
        list_provinsi = [
            {"nama": item.get("label", ""), "kode": item.get("kode_wilayah", "")}
            for item in main_data_nasional.get("data", [])
            if item.get("label", "").lower() != "indonesia" and item.get("kode_wilayah", "")
        ]

        df_year_list = []
        for prov in tqdm(list_provinsi, desc=f"{year} {commodity_name[:15]}..."):
            time.sleep(0.3) 
            raw_prov = get_bps_data(year, active_id, prov["kode"])
            df_prov = parse_bps_simdasi_province_data(raw_prov, year, prov["nama"], commodity_keywords, commodity_column_name)
            if not df_prov.empty:
                df_year_list.append(df_prov)
                
        if df_year_list:
            commodity_dfs_for_all_years.append(pd.concat(df_year_list, ignore_index=True))

    if commodity_dfs_for_all_years:
        commodity_full_df = pd.concat(commodity_dfs_for_all_years, ignore_index=True)
        if final_merged_df.empty:
            final_merged_df = commodity_full_df
        else:
            final_merged_df = pd.merge(final_merged_df, commodity_full_df, on=['tahun', 'provinsi', 'kode_wilayah'], how='outer')

print("\\n🏁 Proses scraping selesai.")""")

    md("""### 1.4 Generate Data Dummy BPS""")

    code("""# =========================================================
# 1.4 GENERATE DUMMY DATA BPS
# =========================================================
# Termasuk kolom produksi_daging_sapi karena tidak cukup tersedia di API
provinsi_list = [
    "Aceh","Sumatera Utara","Sumatera Barat","Riau","Kepulauan Riau","Jambi",
    "Sumatera Selatan","Bangka Belitung","Bengkulu","Lampung","DKI Jakarta",
    "Jawa Barat","Jawa Tengah","DI Yogyakarta","Jawa Timur","Banten","Bali",
    "Nusa Tenggara Barat","Nusa Tenggara Timur","Kalimantan Barat",
    "Kalimantan Tengah","Kalimantan Selatan","Kalimantan Timur",
    "Kalimantan Utara","Sulawesi Utara","Sulawesi Tengah","Sulawesi Selatan",
    "Sulawesi Tenggara","Gorontalo","Sulawesi Barat","Maluku","Maluku Utara",
    "Papua","Papua Barat","Papua Selatan","Papua Tengah",
    "Papua Pegunungan","Papua Barat Daya"
]

def generate_bps_dummy():
    data = []
    for prov in provinsi_list:
        base_pop = random.randint(500000, 50000000)
        for tahun in YEARS:
            growth = round(random.uniform(-0.02, 0.04), 4)
            jumlah_penduduk = int(base_pop * (1 + growth))
            
            populasi_sapi = random.randint(10000, 500000)
            populasi_ayam = random.randint(50000, 5000000)
            
            potong_sapi = int(populasi_sapi * random.uniform(0.4, 0.7))
            potong_ayam = int(populasi_ayam * random.uniform(0.5, 0.8))
            
            produksi_sapi = round(potong_sapi * random.uniform(0.2, 0.3), 2)
            produksi_ayam = round(potong_ayam * random.uniform(0.1, 0.2), 2)
            
            konsumsi_sapi = round(random.uniform(1.5, 3.5), 2)
            konsumsi_ayam = round(random.uniform(8, 15), 2)
            
            permintaan_sapi = round(jumlah_penduduk * konsumsi_sapi / 1000, 2)
            permintaan_ayam = round(jumlah_penduduk * konsumsi_ayam / 1000, 2)
            
            harga_sapi = random.randint(90000, 130000)
            harga_ayam = random.randint(20000, 40000)
            
            # Status Supply 
            ratio = produksi_sapi * 1000 / permintaan_sapi if permintaan_sapi > 0 else 0
            status_supply = "Surplus" if ratio > 0.9 else "Aman" if ratio > 0.7 else "Defisit"

            row = {
                "provinsi": prov,
                "tahun": tahun,
                "jumlah_penduduk_dummy": jumlah_penduduk,
                "populasi_sapi_dummy": populasi_sapi,
                "populasi_ayam_dummy": populasi_ayam,
                "produksi_daging_sapi": produksi_sapi,
                "produksi_daging_ayam_dummy": produksi_ayam,
                "konsumsi_daging_sapi": konsumsi_sapi,
                "konsumsi_daging_ayam": konsumsi_ayam,
                "permintaan_daging_sapi": permintaan_sapi,
                "permintaan_daging_ayam": permintaan_ayam,
                "jumlah_ternak_sapi_potong": potong_sapi,
                "jumlah_ternak_ayam_potong": potong_ayam,
                "harga_baseline_sapi": harga_sapi,
                "harga_baseline_ayam": harga_ayam,
                "growth_populasi": growth,
                "status_supply": status_supply
            }

            if random.random() < 0.05:
                row["produksi_daging_sapi"] = None
            if random.random() < 0.05:
                row["permintaan_daging_ayam"] = None

            data.append(row)

    return pd.DataFrame(data)

df_dummy = generate_bps_dummy()
print("✅ Generate dummy selesai.")

# Menggabungkan Scraping dan Dummy secara langsung
# Note: TIDAK ADA PEMBERSIHAN DATA (CLEANING) disini sesuai instruksi fase extract.
df_dummy['provinsi'] = df_dummy['provinsi'].str.strip()

if not final_merged_df.empty:
    final_merged_df['provinsi'] = final_merged_df['provinsi'].str.strip()
    
    # Merge
    df_gabung = pd.merge(df_dummy, final_merged_df, on=['provinsi', 'tahun'], how='left')
    
    # Gunakan hasil API jika ada, jika tidak gunakan dummy (tanpa merubah format tipe string API)
    df_gabung['jumlah_penduduk'] = df_gabung['jumlah_penduduk'].combine_first(df_gabung['jumlah_penduduk_dummy'])
    df_gabung['populasi_sapi_potong'] = df_gabung['populasi_sapi_potong'].combine_first(df_gabung['populasi_sapi_dummy'])
    df_gabung['populasi_ayam_pedaging'] = df_gabung['populasi_ayam_pedaging'].combine_first(df_gabung['populasi_ayam_dummy'])
    df_gabung['produksi_daging_ayam_pedaging'] = df_gabung['produksi_daging_ayam_pedaging'].combine_first(df_gabung['produksi_daging_ayam_dummy'])
else:
    df_gabung = df_dummy.copy()
    df_gabung['jumlah_penduduk'] = df_gabung['jumlah_penduduk_dummy']
    df_gabung['populasi_sapi_potong'] = df_gabung['populasi_sapi_dummy']
    df_gabung['populasi_ayam_pedaging'] = df_gabung['populasi_ayam_dummy']
    df_gabung['produksi_daging_ayam_pedaging'] = df_gabung['produksi_daging_ayam_dummy']""")

    md("""### 1.5 Memecah Menjadi 4 Tabel Relasional dan Injeksi ke `bps_db`
Sesuai instruksi, pada fase ekstrak data BPS ini kita akan langsung menginjeksinya ke dalam tabel relasional PostgreSQL `bps_db` sebagai Operational Source Database. DDL `CREATE TABLE` diterapkan di sini.""")

    code("""# =========================================================
# 1.5 PEMBUATAN 4 TABEL BPS & INJEKSI KE bps_db
# =========================================================

# Buat mapping provinsi berdasarkan list BPS
prov_map = {p: i for i, p in enumerate(sorted(df_gabung['provinsi'].unique()), 1)}

# 1. ref_wilayah
df_ref_wilayah = pd.DataFrame(list(prov_map.items()), columns=['nama_provinsi', 'kode_wilayah'])
df_ref_wilayah = df_ref_wilayah[['kode_wilayah', 'nama_provinsi']]

# 2. ref_komoditas
df_ref_komoditas = pd.DataFrame({
    'id_komoditas': [1, 2],
    'nama_komoditas': ['Sapi', 'Ayam'],
    'satuan_berat': ['Ton', 'Kg']
})

# Menambahkan kolom kode_wilayah ke df_gabung
df_gabung['kode_wilayah'] = df_gabung['provinsi'].map(prov_map)

# 3. tr_demografi_tahunan
df_tr_demografi = df_gabung[['kode_wilayah', 'tahun', 'jumlah_penduduk', 'growth_populasi']].copy()
# Di sini kita biarkan tipe datanya as-is untuk extract, namun untuk masuk postgres kita pastikan numeric
# (Catatan: API BPS raw value butuh konversi jika string)
df_tr_demografi['jumlah_penduduk'] = pd.to_numeric(df_tr_demografi['jumlah_penduduk'], errors='coerce')

# 4. tr_statistik_peternakan
# Untuk Sapi
df_sapi = df_gabung[['kode_wilayah', 'tahun', 'populasi_sapi_potong', 'produksi_daging_sapi', 
                     'konsumsi_daging_sapi', 'permintaan_daging_sapi', 'jumlah_ternak_sapi_potong', 'harga_baseline_sapi']].copy()
df_sapi.columns = ['kode_wilayah', 'tahun', 'populasi', 'produksi', 'konsumsi_per_kapita', 'permintaan_ekor', 'jumlah_dipotong', 'harga_baseline']
df_sapi['id_komoditas'] = 1

# Untuk Ayam
df_ayam = df_gabung[['kode_wilayah', 'tahun', 'populasi_ayam_pedaging', 'produksi_daging_ayam_pedaging', 
                     'konsumsi_daging_ayam', 'permintaan_daging_ayam', 'jumlah_ternak_ayam_potong', 'harga_baseline_ayam']].copy()
df_ayam.columns = ['kode_wilayah', 'tahun', 'populasi', 'produksi', 'konsumsi_per_kapita', 'permintaan_ekor', 'jumlah_dipotong', 'harga_baseline']
df_ayam['id_komoditas'] = 2

df_tr_statistik = pd.concat([df_sapi, df_ayam], ignore_index=True)

# Konversi kolom populasi dkk ke numeric agar bisa masuk postgres
for col in ['populasi', 'produksi', 'konsumsi_per_kapita', 'permintaan_ekor', 'jumlah_dipotong', 'harga_baseline']:
    df_tr_statistik[col] = pd.to_numeric(df_tr_statistik[col], errors='coerce')

# Eksekusi DDL ke bps_db
DDL_QUERIES = \"\"\"
DROP TABLE IF EXISTS tr_statistik_peternakan;
DROP TABLE IF EXISTS tr_demografi_tahunan;
DROP TABLE IF EXISTS ref_komoditas;
DROP TABLE IF EXISTS ref_wilayah;

CREATE TABLE ref_wilayah (
    kode_wilayah INT PRIMARY KEY,
    nama_provinsi VARCHAR(100) NOT NULL
);

CREATE TABLE ref_komoditas (
    id_komoditas INT PRIMARY KEY,
    nama_komoditas VARCHAR(50) NOT NULL,
    satuan_berat VARCHAR(10)
);

CREATE TABLE tr_demografi_tahunan (
    kode_wilayah INT NOT NULL,
    tahun INT NOT NULL,
    jumlah_penduduk BIGINT,
    growth_populasi DECIMAL(5, 4),
    PRIMARY KEY (kode_wilayah, tahun),
    FOREIGN KEY (kode_wilayah) REFERENCES ref_wilayah(kode_wilayah)
);

CREATE TABLE tr_statistik_peternakan (
    kode_wilayah INT NOT NULL,
    tahun INT NOT NULL,
    id_komoditas INT NOT NULL,
    populasi BIGINT,
    produksi DECIMAL(15, 2),
    konsumsi_per_kapita DECIMAL(10, 2),
    permintaan_ekor BIGINT,
    jumlah_dipotong BIGINT,
    harga_baseline DECIMAL(15, 2),
    PRIMARY KEY (kode_wilayah, tahun, id_komoditas),
    FOREIGN KEY (kode_wilayah) REFERENCES ref_wilayah(kode_wilayah),
    FOREIGN KEY (id_komoditas) REFERENCES ref_komoditas(id_komoditas)
);
\"\"\"

print("📦 Mengeksekusi DDL di bps_db...")
with engine_bps.connect() as conn:
    for query in DDL_QUERIES.strip().split(';'):
        if query.strip():
            conn.execute(text(query.strip() + ';'))
    conn.commit()

# Load data ke bps_db
print("📤 Mengirim data ke bps_db...")
df_ref_wilayah.to_sql('ref_wilayah', engine_bps, if_exists='append', index=False)
df_ref_komoditas.to_sql('ref_komoditas', engine_bps, if_exists='append', index=False)
df_tr_demografi.to_sql('tr_demografi_tahunan', engine_bps, if_exists='append', index=False)
df_tr_statistik.to_sql('tr_statistik_peternakan', engine_bps, if_exists='append', index=False)

print("✅ Data BPS (Scraping + Dummy) sukses diload ke bps_db.")""")

    md("""---
## 2. EXTRACT DATA iSIKHNAS
Data iSIKHNAS sudah tersedia di MySQL `isikhnas_db`. Pada fase extract ini, kita hanya bertugas memindahkannya (mereplika) ke dalam PostgreSQL `staging_db`.""")

    code("""# =========================================================
# 2. EXTRACT ISIKHNAS DARI MYSQL KE POSTGRES STAGING
# =========================================================

ISIKHNAS_TABLES = [
    "ref_hewan",
    "ref_wilayah",
    "tr_mutasi",
    "tr_laporan_sakit",
    "tr_hasil_lab",
    "tr_rph"
]

print("🔄 Mengekstrak data iSIKHNAS dari MySQL ke PostgreSQL (staging_db)...")
for table in ISIKHNAS_TABLES:
    try:
        # Tarik data utuh dari MySQL
        df_isikhnas = pd.read_sql(f"SELECT * FROM {table}", engine_isikhnas)
        
        # Load langsung ke Postgres staging_db dengan prefix agar tidak bentrok
        staging_table_name = f"stg_isikhnas_{table}"
        df_isikhnas.to_sql(staging_table_name, engine_staging, if_exists='replace', index=False)
        print(f"  ✅ Tabel {table} berhasil diekstrak ({len(df_isikhnas)} baris).")
    except Exception as e:
        print(f"  ❌ Gagal ekstrak tabel {table}: {e}")""")

    md("""---
## 3. EXTRACT DATA PIHPS (HARGA HARIAN CSV)
Data harga pangan dari PIHPS bersumber dari file CSV/Excel `final_data.xlsx`. Data akan dimuat langsung ke `staging_db`.""")

    code("""# =========================================================
# 3. EXTRACT PIHPS DARI EXCEL KE POSTGRES STAGING
# =========================================================

PIHPS_FILE = "../DATA/PIHPS/final_data.xlsx"

print("🔄 Mengekstrak data PIHPS dari Excel ke PostgreSQL (staging_db)...")
if os.path.exists(PIHPS_FILE):
    try:
        df_pihps = pd.read_excel(PIHPS_FILE)
        
        # Sesuai aturan extract, tanpa pembersihan ekstrim, langsung dump
        df_pihps.to_sql("stg_pihps_raw", engine_staging, if_exists='replace', index=False)
        print(f"  ✅ Data PIHPS berhasil diekstrak ({len(df_pihps)} baris).")
    except Exception as e:
        print(f"  ❌ Gagal memuat file Excel PIHPS: {e}")
else:
    print(f"  ❌ File PIHPS tidak ditemukan di path: {PIHPS_FILE}")""")

    with open(r'd:\STIS SEM 6\TPD\TPD UTS KELOMPOK 1\CODE\ETL_Extract_Kelompok1.ipynb', 'w', encoding='utf-8') as f:
        json.dump(nb, f, indent=2)

create_notebook()
print("Selesai")
