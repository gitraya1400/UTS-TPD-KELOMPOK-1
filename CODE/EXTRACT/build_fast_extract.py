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

    # Cell 0
    md("""# ETL Pipeline: Livestock Intelligence - FASE 1 (EXTRACT)
**Laporan Praktikum Teknologi Perekayasaan Data - Kelompok 1 (3SI1)**

## Scope Extract Sesuai Arsitektur ETL
Fase ini **hanya bertugas mengekstrak (menarik) data mentah** dari berbagai sumber dan memuatnya langsung ke *Staging Area* (PostgreSQL `staging_db`) apa adanya (as-is). 
- ❌ **TIDAK ADA** normalisasi atau *unpivot*
- ❌ **TIDAK ADA** *surrogate key* (pembuatan ID baru)
- ❌ **TIDAK ADA** DDL *constraint* (Primary Key, Foreign Key)
- ❌ **TIDAK ADA** *cleaning* secara manual
- ❌ **TIDAK ADA** logika bisnis atau kalkulasi turunan

Semua proses pembersihan lanjutan dan pembentukan skema bintang akan dilakukan di fase **Transform**.""")

    # Cell 1
    code("""# =========================================================
# IMPORT LIBRARY & KONFIGURASI DATABASE
# =========================================================
import requests
import pandas as pd
import numpy as np
import random
import time
import os
from tqdm import tqdm
from IPython.display import display
from sqlalchemy import create_engine, text

import warnings
warnings.filterwarnings('ignore')
random.seed(42)

# --- KONEKSI POSTGRESQL (STAGING_DB) ---
PG_USER = 'postgres'
PG_PASS = 'postgres'
PG_HOST = 'localhost'
PG_PORT = '5432'
engine_staging = create_engine(f'postgresql+psycopg2://{PG_USER}:{PG_PASS}@{PG_HOST}:{PG_PORT}/staging_db')

# --- KONEKSI MYSQL (ISIKHNAS_DB) ---
MYSQL_USER = 'root'
MYSQL_PASS = ''
MYSQL_HOST = 'localhost'
MYSQL_PORT = '3306'
engine_isikhnas = create_engine(f'mysql+pymysql://{MYSQL_USER}:{MYSQL_PASS}@{MYSQL_HOST}:{MYSQL_PORT}/isikhnas_db')

PIHPS_FILE = "../DATA/PIHPS/final_data.xlsx"
print("✅ Modul dan Konfigurasi Koneksi Berhasil Dimuat.")""")

    # Cell 2
    md("""## 1. EXTRACT DATA BPS (API & DUMMY)
Menarik data dari BPS SIMDASI melalui Web API dengan metode per-provinsi agar stabil.""")

    # Cell 3
    code("""# ============================================================
# CELL 3 · KONFIGURASI API BPS & FUNGSI INTI SCRAPING
# ============================================================
API_KEY = "d328d5f200379241367024848106698e"
YEARS   = [2020, 2021, 2022, 2023, 2024, 2025]

COMMODITIES_TO_SCRAPE = [
    {
        "name"      : "Jumlah Penduduk",
        "table_ids" : ["WVRlTTcySlZDa3lUcFp6czNwbHl4QT09"],
        "keywords"  : ["jumlah", "penduduk"],
        "col"       : "jumlah_penduduk",
    },
    {
        "name"      : "Populasi Sapi Potong",
        "table_ids" : ["S2ViU1dwVTlpSXRwU1MvendHN05Cdz09"],
        "keywords"  : ["populasi", "sapi", "potong"],
        "col"       : "populasi_sapi",
    },
    {
        "name"      : "Populasi Ayam Pedaging",
        "table_ids" : ["ckJyVXRMT05MWTNpaW9mdnVseFk0Zz09"],
        "keywords"  : ["populasi", "ayam", "pedaging"],
        "col"       : "populasi_ayam",
    },
    {
        "name"      : "Produksi Daging Ayam Pedaging",
        "table_ids" : ["dWhmNFl6WXYyR093R2NjTGM3NG9idz09"],
        "keywords"  : ["produksi", "daging", "ayam", "pedaging"],
        "col"       : "produksi_daging_ayam",
    },
]

def get_bps_data(year, table_id, kode_wilayah="0000000"):
    url = f"https://webapi.bps.go.id/v1/api/interoperabilitas/datasource/simdasi/id/25/tahun/{year}/id_tabel/{table_id}/wilayah/{kode_wilayah}/key/{API_KEY}"
    try:
        r = requests.get(url, timeout=30)
        return r.json()
    except Exception:
        return None

def get_target_var_id(main_data, target_keywords):
    for var_id, info in main_data.get("kolom", {}).items():
        nama = str(info.get("nama_variabel", "")).lower()
        if all(kw in nama for kw in target_keywords):
            return var_id
    return None

print("✅ Fungsi scraping berhasil didefinisikan.")""")

    # Cell 4
    md("""### Pre-flight Check""")

    # Cell 5
    code("""# =========================================================
# PRE-FLIGHT CHECK
# =========================================================
print("="*60)
print(" PRE-FLIGHT CHECK API BPS ")
print("="*60)

year_to_check = 2023 
for commodity_info in COMMODITIES_TO_SCRAPE:
    commodity_name = commodity_info["name"]
    table_ids = commodity_info["table_ids"]
    keywords = commodity_info["keywords"]
    
    status_ok = False
    for tbl_id in table_ids:
        temp_data = get_bps_data(year_to_check, tbl_id, "0000000")
        if temp_data and temp_data.get("status") == "OK":
            main_data_check = temp_data.get("data", [{}, {}])[1]
            if get_target_var_id(main_data_check, keywords):
                print(f"✅ {commodity_name.ljust(35)}: OK (Tabel {tbl_id})")
                status_ok = True
                break
    
    if not status_ok:
        print(f"❌ {commodity_name.ljust(35)}: GAGAL")""")

    # Cell 6
    md("""### Pelaksanaan Scraping BPS (Iterasi per Provinsi)""")

    # Cell 7
    code("""# ============================================================
# CELL 7 · SCRAPING API BPS — FULL RUN (METODE ITERASI PROVINSI)
# ============================================================
print("🚀 Memulai scraping BPS...")

commodity_dfs = {}

for comm in COMMODITIES_TO_SCRAPE:
    print(f"\\n--- [{comm['name']}] ---")
    yearly_dfs = []

    for year in YEARS:
        # Cari active_id dengan menembak data nasional sekali
        active_id = None
        var_id = None
        list_provinsi = []
        
        for tbl_id in comm["table_ids"]:
            raw_nasional = get_bps_data(year, tbl_id, "0000000")
            if raw_nasional and raw_nasional.get("status") == "OK":
                main_data = raw_nasional.get("data", [{}, {}])[1]
                var_id = get_target_var_id(main_data, comm["keywords"])
                if var_id:
                    active_id = tbl_id
                    for item in main_data.get("data", []):
                        nama_prov = item.get("label", "").strip()
                        kode = item.get("kode_wilayah", "")
                        if kode and nama_prov.lower() not in ("indonesia", ""):
                            list_provinsi.append({"nama": nama_prov, "kode": kode})
                    break
                    
        if not active_id or not list_provinsi:
            continue
            
        rows = []
        for prov in tqdm(list_provinsi, desc=f"  {comm['col']} {year}", ncols=70):
            time.sleep(0.1) # Jaga rate-limit ringan
            raw_prov = get_bps_data(year, active_id, prov["kode"])
            if not raw_prov or raw_prov.get("status") != "OK":
                continue
                
            main_prov = raw_prov.get("data", [{}, {}])[1]
            val = None
            for item in main_prov.get("data", []):
                if item.get("kode_wilayah", "") == prov["kode"]:
                    vars_data = item.get("variables", {})
                    if var_id in vars_data:
                        val = vars_data[var_id].get("value_raw", None)
                    break
                    
            rows.append({
                "provinsi": prov["nama"],
                "tahun": year,
                comm["col"]: val
            })
            
        if rows:
            yearly_dfs.append(pd.DataFrame(rows))

    if yearly_dfs:
        commodity_dfs[comm["col"]] = pd.concat(yearly_dfs, ignore_index=True)
        print(f"   ✅ {len(commodity_dfs[comm['col']])} baris terkumpul")
    else:
        print(f"   ❌ Tidak ada data berhasil diambil untuk {comm['name']}")

print()
# Merge semua komoditas
if commodity_dfs:
    keys = list(commodity_dfs.keys())
    df_scraped = commodity_dfs[keys[0]]

    for col in keys[1:]:
        df_scraped = df_scraped.merge(commodity_dfs[col], on=["provinsi", "tahun"], how="outer")

    df_scraped["provinsi"] = df_scraped["provinsi"].str.strip()
    print(f"✅ Hasil scraping: {df_scraped.shape[0]} baris × {df_scraped.shape[1]} kolom")
    display(df_scraped.head(10))
else:
    df_scraped = pd.DataFrame()""")

    # Cell 8
    md("""### Generate Dummy BPS""")

    # Cell 9
    code("""# =========================================================
# GENERATE DUMMY BPS (TANPA LOGIKA BISNIS)
# =========================================================
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
            
            row = {
                "provinsi": prov,
                "tahun": tahun,
                "jumlah_penduduk_dummy": jumlah_penduduk,
                "populasi_sapi_dummy": populasi_sapi,
                "populasi_ayam_dummy": populasi_ayam,
                "produksi_daging_sapi_dummy": produksi_sapi,
                "produksi_daging_ayam_dummy": produksi_ayam,
                "konsumsi_daging_sapi_dummy": konsumsi_sapi,
                "konsumsi_daging_ayam_dummy": konsumsi_ayam,
                "permintaan_daging_sapi_dummy": permintaan_sapi,
                "permintaan_daging_ayam_dummy": permintaan_ayam,
                "jumlah_ternak_sapi_potong_dummy": potong_sapi,
                "jumlah_ternak_ayam_potong_dummy": potong_ayam,
                "harga_baseline_sapi_dummy": harga_sapi,
                "harga_baseline_ayam_dummy": harga_ayam,
                "growth_populasi_dummy": growth
            }

            if random.random() < 0.05:
                row["produksi_daging_sapi_dummy"] = None

            data.append(row)

    return pd.DataFrame(data)

df_bps_dummy_raw = generate_bps_dummy()
print("✅ Generate dummy selesai.")""")

    # Cell 10
    md("""### Push Staging BPS""")

    # Cell 11
    code("""# =========================================================
# PUSH KE POSTGRESQL (STAGING BPS)
# =========================================================
print("📤 Mengirim data raw BPS ke staging_db...")
if not df_scraped.empty:
    df_scraped.to_sql('staging_bps_api_raw', engine_staging, if_exists='replace', index=False)
df_bps_dummy_raw.to_sql('staging_bps_dummy_raw', engine_staging, if_exists='replace', index=False)
print("✅ Tabel staging_bps_api_raw dan staging_bps_dummy_raw berhasil dimuat.")""")

    # Cell 12
    md("""## 2. EXTRACT DATA iSIKHNAS""")

    # Cell 13
    code("""# =========================================================
# EXTRACT iSIKHNAS DARI MYSQL -> POSTGRESQL (STAGING)
# =========================================================
ISIKHNAS_TABLES = [
    "ref_hewan",
    "ref_wilayah",
    "tr_mutasi",
    "tr_laporan_sakit",
    "tr_hasil_lab",
    "tr_rph"
]

print("🔄 Mengekstrak data iSIKHNAS...")
for table in ISIKHNAS_TABLES:
    try:
        df_isikhnas = pd.read_sql(f"SELECT * FROM {table}", engine_isikhnas)
        staging_table_name = f"staging_isikhnas_{table}"
        df_isikhnas.to_sql(staging_table_name, engine_staging, if_exists='replace', index=False)
        print(f"  ✅ {table} berhasil diekstrak ({len(df_isikhnas)} baris) -> {staging_table_name}")
    except Exception as e:
        print(f"  ❌ Gagal ekstrak tabel {table}: {e}")""")

    # Cell 14
    md("""## 3. EXTRACT DATA PIHPS (HARGA HARIAN)""")

    # Cell 15
    code("""# =========================================================
# EXTRACT PIHPS (EXCEL) -> POSTGRESQL (STAGING)
# =========================================================
print("🔄 Mengekstrak data PIHPS...")
if os.path.exists(PIHPS_FILE):
    try:
        df_pihps = pd.read_excel(PIHPS_FILE)
        df_pihps.to_sql("staging_pihps_raw", engine_staging, if_exists='replace', index=False)
        print(f"  ✅ Data PIHPS berhasil diekstrak ({len(df_pihps)} baris) -> staging_pihps_raw")
    except Exception as e:
        print(f"  ❌ Gagal memuat file Excel PIHPS: {e}")
else:
    print(f"  ❌ File PIHPS tidak ditemukan di path: {PIHPS_FILE}")""")

    # Cell 16
    md("""## VALIDASI STAGING AREA""")

    # Cell 17
    code("""# =========================================================
# VALIDASI TABEL DI STAGING_DB
# =========================================================
print("="*50)
print(" REKAPITULASI TABEL STAGING AREA ")
print("="*50)

try:
    with engine_staging.connect() as conn:
        tables = conn.execute(text(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
        )).fetchall()
        
        if not tables:
            print("Tidak ada tabel ditemukan di public schema staging_db.")
        
        for t in sorted([t[0] for t in tables]):
            count = conn.execute(text(f"SELECT COUNT(*) FROM {t}")).scalar()
            print(f"- {t.ljust(30)} : {count} baris")
except Exception as e:
    print(f"Gagal melakukan validasi: {e}")""")

    with open(r'd:\STIS SEM 6\TPD\TPD UTS KELOMPOK 1\CODE\ETL_Extract_Kelompok1 CLAUDE .ipynb', 'w', encoding='utf-8') as f:
        json.dump(nb, f, indent=2)
        
    with open(r'd:\STIS SEM 6\TPD\TPD UTS KELOMPOK 1\CODE\ETL_Extract_Kelompok1.ipynb', 'w', encoding='utf-8') as f:
        json.dump(nb, f, indent=2)

create_notebook()
print("Selesai")
