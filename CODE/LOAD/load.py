#!/usr/bin/env python
# coding: utf-8

# # ETL Pipeline: Livestock Intelligence — FASE 3 (LOAD)

# INISIALISASI SPARK SESSION

import os
os.environ["PYSPARK_PYTHON"]        = r"C:\Users\anggi\AppData\Local\Programs\Python\Python310\python.exe"
os.environ["PYSPARK_DRIVER_PYTHON"] = r"C:\Users\anggi\AppData\Local\Programs\Python\Python310\python.exe"
os.environ["HADOOP_HOME"] = "C:/hadoop"
os.environ["PATH"]       += ";C:/hadoop/bin"

import warnings
warnings.filterwarnings('ignore')

import psycopg2
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import DoubleType, IntegerType, LongType, StringType
from pyspark.sql.functions import lit

# --- KONFIGURASI ---
PG_USER    = 'postgres'
PG_PASS    = 'mydatabase'
PG_HOST    = 'localhost'
PG_PORT    = '5432'
DW_DB      = 'datawarehouse_db'

JDBC_JAR = "C:/Users/anggi/Documents/KULIAH/TINGKAT 3/SEMESTER 6/TPD/PROJECT UTS/UTS-TPD-KELOMPOK-1/postgresql-42.7.11.jar"
TRANSFORM_DIR = r"C:\Users\anggi\Documents\KULIAH\TINGKAT 3\SEMESTER 6\TPD\PROJECT UTS\UTS-TPD-KELOMPOK-1\DATA\TRANSFORM_OUTPUT"

DW_JDBC_URL   = f"jdbc:postgresql://{PG_HOST}:{PG_PORT}/{DW_DB}"
DW_JDBC_PROPS = {
    "user":     PG_USER,
    "password": PG_PASS,
    "driver":   "org.postgresql.Driver"
}

conn_pg = psycopg2.connect(
    dbname='postgres', user=PG_USER, password=PG_PASS,
    host=PG_HOST, port=int(PG_PORT)
)
conn_pg.autocommit = True
cur = conn_pg.cursor()
cur.execute(f"SELECT 1 FROM pg_database WHERE datname = '{DW_DB}'")
if not cur.fetchone():
    cur.execute(f'CREATE DATABASE {DW_DB}')
    print(f'  NEW Database "{DW_DB}" berhasil dibuat.')
else:
    print(f'  OK  Database "{DW_DB}" sudah ada.')
cur.close()
conn_pg.close()

# SPARK SESSION
try:
    spark.stop()
except:
    pass

spark = (SparkSession.builder
    .appName("Livestock Intelligence - Load")
    .config("spark.jars",                          JDBC_JAR)
    .config("spark.driver.extraClassPath",         JDBC_JAR)
    .config("spark.executor.extraClassPath",       JDBC_JAR)
    .config("spark.sql.legacy.timeParserPolicy",   "LEGACY")
    .config("spark.driver.memory",                 "4g")
    .config("spark.driver.host",                   "127.0.0.1")
    .config("spark.driver.bindAddress",            "127.0.0.1")
    .config("spark.python.worker.reuse",           "false")
    .config("spark.hadoop.io.native.lib.available","false")
    .config("spark.hadoop.fs.file.impl",           "org.apache.hadoop.fs.RawLocalFileSystem")
    .getOrCreate())

spark.sparkContext.setLogLevel("WARN")
print("OK  SparkSession berhasil diinisialisasi.")
print(f"    Spark version : {spark.version}")
print(f"    Target DW     : {DW_JDBC_URL}")

# DDL SCHEMA TABEL DI DATA WAREHOUSE

DDL_STATEMENTS = """
DROP TABLE IF EXISTS public.fact_supply_resilience CASCADE;
DROP TABLE IF EXISTS public.dim_waktu              CASCADE;
DROP TABLE IF EXISTS public.dim_komoditas          CASCADE;
DROP TABLE IF EXISTS public.dim_prov               CASCADE;

CREATE TABLE public.dim_prov (
    prov_key        INTEGER PRIMARY KEY,
    id_prov         INTEGER,               
    nama_provinsi   VARCHAR(100) NOT NULL
);

CREATE TABLE public.dim_komoditas (
    komoditas_key   INTEGER PRIMARY KEY,
    id_komoditas    INTEGER,               
    nama_komoditas  VARCHAR(100) NOT NULL
);

CREATE TABLE public.dim_waktu (
    waktu_key       INTEGER PRIMARY KEY,
    tahun           SMALLINT NOT NULL,
    bulan           SMALLINT NOT NULL,
    kuartal         SMALLINT,
    nama_bulan      VARCHAR(20),
    UNIQUE (tahun, bulan)
);

CREATE TABLE public.fact_supply_resilience (
    fact_id                  SERIAL PRIMARY KEY,
    prov_key                 INTEGER NOT NULL REFERENCES public.dim_prov(prov_key),
    waktu_key                INTEGER NOT NULL REFERENCES public.dim_waktu(waktu_key),
    komoditas_key            INTEGER NOT NULL REFERENCES public.dim_komoditas(komoditas_key),
    jumlah_penduduk          BIGINT,
    sum_jumlah_sakit         DOUBLE PRECISION,
    sum_jumlah_mati          DOUBLE PRECISION,
    sum_vol_mutasi           DOUBLE PRECISION,
    sum_realisasi_karkas     DOUBLE PRECISION,
    avg_harga                DOUBLE PRECISION,
    harga_baseline           DOUBLE PRECISION,
    populasi_ternak          DOUBLE PRECISION,
    avg_konsumsi_bulanan     DOUBLE PRECISION,
    avg_pemotongan_bulanan   DOUBLE PRECISION,
    growth_populasi          DOUBLE PRECISION,
    avg_permintaan_bulanan   DOUBLE PRECISION,
    avg_produksi_bulanan     DOUBLE PRECISION,
    supply_risk_index        DOUBLE PRECISION,
    UNIQUE (prov_key, waktu_key, komoditas_key)
);

CREATE INDEX idx_fact_prov       ON public.fact_supply_resilience (prov_key);
CREATE INDEX idx_fact_waktu      ON public.fact_supply_resilience (waktu_key);
CREATE INDEX idx_fact_komoditas  ON public.fact_supply_resilience (komoditas_key);
CREATE INDEX idx_fact_risk       ON public.fact_supply_resilience (supply_risk_index DESC);
"""

conn_dw = psycopg2.connect(
    dbname=DW_DB, user=PG_USER, password=PG_PASS,
    host=PG_HOST, port=int(PG_PORT)
)
conn_dw.autocommit = False
try:
    cur = conn_dw.cursor()
    cur.execute(DDL_STATEMENTS)
    conn_dw.commit()
    print('OK  DDL berhasil dieksekusi.')
    cur.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' ORDER BY table_name
    """)
    print('    Tabel di datawarehouse_db:')
    for t in cur.fetchall():
        print(f'      - public.{t[0]}')
except Exception as e:
    conn_dw.rollback()
    raise e
finally:
    cur.close()
    conn_dw.close()

# BACA FILE PARQUET -> SPARK DATAFRAME

def read_parquet(name: str):
    """Baca tabel Parquet dari TRANSFORM_OUTPUT."""
    path_dir  = os.path.join(TRANSFORM_DIR, name)
    path_file = path_dir + '.parquet'

    if os.path.isdir(path_dir):
        sdf = spark.read.parquet(path_dir)
    elif os.path.isfile(path_file):
        sdf = spark.read.parquet(path_file)
    else:
        raise FileNotFoundError(
            f"Parquet tidak ditemukan: {path_dir} atau {path_file}\n"
            f"Pastikan Fase Transform sudah dijalankan terlebih dahulu."
        )

    for col in sdf.columns:
        if col != col.lower():
            sdf = sdf.withColumnRenamed(col, col.lower())

    n = sdf.count()
    print(f'  - {name:<30} -> {n:>5} baris, {len(sdf.columns)} kolom')
    return sdf


print('Membaca file Parquet dari TRANSFORM_OUTPUT...\n')

sdf_dim_prov      = read_parquet('dim_prov')
sdf_dim_komoditas = read_parquet('dim_komoditas')
sdf_dim_waktu     = read_parquet('dim_waktu')
sdf_fact          = read_parquet('fact_supply_resilience')

print('\nOK  Semua Parquet berhasil dibaca ke Spark DataFrame.')

# VALIDASI PRE-LOAD

print('=' * 65)
print('  VALIDASI PRE-LOAD')
print('=' * 65)

errors = []

print('\n-- [1] Cek Kolom Wajib --')
required_cols = {
    'dim_prov'      : (sdf_dim_prov,      ['prov_key', 'nama_provinsi']),
    'dim_komoditas' : (sdf_dim_komoditas,  ['komoditas_key', 'nama_komoditas']),
    'dim_waktu'     : (sdf_dim_waktu,      ['waktu_key', 'tahun', 'bulan']),
    'fact'          : (sdf_fact,           ['prov_key', 'waktu_key', 'komoditas_key', 'supply_risk_index']),
}
for tbl, (sdf, cols) in required_cols.items():
    missing = [c for c in cols if c not in sdf.columns]
    if missing:
        errors.append(f'{tbl}: kolom {missing} tidak ada!')
        print(f'  FAIL {tbl:<20} -> kolom hilang: {missing}')
    else:
        print(f'  OK   {tbl:<20} -> semua kolom wajib ada')

print('\n-- [2] Cek NULL pada Foreign Key --')
for col in ['prov_key', 'waktu_key', 'komoditas_key']:
    if col in sdf_fact.columns:
        n_null = sdf_fact.filter(F.col(col).isNull()).count()
        if n_null > 0:
            errors.append(f'fact.{col}: {n_null} NULL!')
            print(f'  FAIL fact.{col:<25} -> {n_null} NULL')
        else:
            print(f'  OK   fact.{col:<25} -> 0 NULL')

print('\n-- [3] Cek Referential Integrity (Spark left_anti join) --')

def check_fk_spark(fact_sdf, dim_sdf, fk_col, pk_col, dim_name):
    if fk_col not in fact_sdf.columns:
        print(f'  SKIP {fk_col}: kolom tidak ditemukan di fact.')
        return
    orphans = (fact_sdf.select(F.col(fk_col))
                       .distinct()
                       .join(dim_sdf.select(F.col(pk_col)),
                             fact_sdf[fk_col] == dim_sdf[pk_col], 'left_anti')
                       .count())
    if orphans > 0:
        errors.append(f'{fk_col} -> {dim_name}: {orphans} orphan key!')
        print(f'  FAIL {fk_col} -> {dim_name:<20} : {orphans} orphan key')
    else:
        print(f'  OK   {fk_col} -> {dim_name:<20} : OK')

check_fk_spark(sdf_fact, sdf_dim_prov,      'prov_key',      'prov_key',      'dim_prov')
check_fk_spark(sdf_fact, sdf_dim_waktu,     'waktu_key',     'waktu_key',     'dim_waktu')
check_fk_spark(sdf_fact, sdf_dim_komoditas, 'komoditas_key', 'komoditas_key', 'dim_komoditas')

print('\n-- [4] Missing Values Fact Table --')
for col_name in sdf_fact.columns:
    n_null = sdf_fact.filter(F.col(col_name).isNull()).count()
    icon = 'WARN' if n_null > 0 else 'OK  '
    print(f'  {icon} {col_name:<35} -> {n_null} null')

print('\n' + '=' * 65)
if errors:
    print(f'  FAIL {len(errors)} ERROR -- STOP!')
    for e in errors:
        print(f'     -> {e}')
    raise ValueError('Validasi pre-load GAGAL. Perbaiki error di atas.')
else:
    print('  OK   Validasi pre-load LULUS -- siap di-load ke Data Warehouse.')

# LOAD TABEL DIMENSI via PySpark JDBC


def execute_sql_pg(sql: str):
    """Jalankan DDL ke PostgreSQL via Py4J — tanpa psycopg2."""
    driver_manager = spark._sc._jvm.java.sql.DriverManager
    conn = driver_manager.getConnection(DW_JDBC_URL, PG_USER, PG_PASS)
    stmt = conn.createStatement()
    stmt.executeUpdate(sql)
    stmt.close()
    conn.close()

def write_jdbc(sdf, table_name: str, cols: list = None):
    sdf_out = sdf.select(cols) if cols else sdf
    for col in sdf_out.columns:
        if col != col.lower():
            sdf_out = sdf_out.withColumnRenamed(col, col.lower())

    try:
        existing_count = spark.read \
            .format("jdbc") \
            .option("url",      DW_JDBC_URL) \
            .option("dbtable",  f"(SELECT COUNT(*) AS n FROM public.{table_name}) t") \
            .option("user",     PG_USER) \
            .option("password", PG_PASS) \
            .option("driver",   "org.postgresql.Driver") \
            .load().collect()[0]['n']
        if existing_count > 0:
            print(f"  🗑️  TRUNCATE {table_name} CASCADE...")
            execute_sql_pg(f'TRUNCATE TABLE public."{table_name}" RESTART IDENTITY CASCADE;')
    except:
        pass  

    sdf_out.write \
        .format("jdbc") \
        .option("url",      DW_JDBC_URL) \
        .option("dbtable",  f"public.{table_name}") \
        .option("user",     PG_USER) \
        .option("password", PG_PASS) \
        .option("driver",   "org.postgresql.Driver") \
        .option("batchsize","500") \
        .mode("append") \
        .save()

    n = spark.read \
        .format("jdbc") \
        .option("url",     DW_JDBC_URL) \
        .option("dbtable", f"(SELECT COUNT(*) AS n FROM public.{table_name}) t") \
        .option("user",    PG_USER) \
        .option("password",PG_PASS) \
        .option("driver",  "org.postgresql.Driver") \
        .load().collect()[0]['n']
    print(f"  [SUCCESS] {table_name:<30} -> {n:>5} baris tersimpan")


print("Loading tabel dimensi ke Data Warehouse...\n")

cols_prov = [c for c in ['prov_key','id_prov','nama_provinsi'] if c in sdf_dim_prov.columns]
write_jdbc(sdf_dim_prov, 'dim_prov', cols_prov)

cols_kom = [c for c in ['komoditas_key','id_komoditas','nama_komoditas'] if c in sdf_dim_komoditas.columns]
write_jdbc(sdf_dim_komoditas, 'dim_komoditas', cols_kom)

cols_wkt = [c for c in ['waktu_key','tahun','bulan','kuartal','nama_bulan'] if c in sdf_dim_waktu.columns]
write_jdbc(sdf_dim_waktu, 'dim_waktu', cols_wkt)

print("\n[SUCCESS]Semua tabel dimensi berhasil di-load.")


# LOAD FACT TABLE via PySpark JDBC

RENAME_MAP = {
    'avg_produksi'   : 'avg_produksi_bulanan',
    'avg_konsumsi'   : 'avg_konsumsi_bulanan',
    'avg_pemotongan' : 'avg_pemotongan_bulanan',
    'avg_permintaan' : 'avg_permintaan_bulanan',
}

# Kolom sesuai DDL fact table
DDL_FACT_COLS = [
    'prov_key', 'waktu_key', 'komoditas_key',
    'jumlah_penduduk',
    'sum_jumlah_sakit', 'sum_jumlah_mati',
    'sum_vol_mutasi', 'sum_realisasi_karkas',
    'avg_harga', 'harga_baseline',
    'populasi_ternak',
    'avg_konsumsi_bulanan', 'avg_pemotongan_bulanan',
    'growth_populasi',
    'avg_permintaan_bulanan', 'avg_produksi_bulanan',
    'supply_risk_index',
]

sdf_fact_load = sdf_fact

for old, new in RENAME_MAP.items():
    if old in sdf_fact_load.columns:
        sdf_fact_load = sdf_fact_load.withColumnRenamed(old, new)
        print(f'  Rename: {old} -> {new}')

for col in DDL_FACT_COLS:
    if col not in sdf_fact_load.columns:
        sdf_fact_load = sdf_fact_load.withColumn(col, lit(None).cast(DoubleType()))
        print(f'  WARN  Kolom "{col}" tidak ada di Parquet -> diisi NULL')

sdf_fact_load = sdf_fact_load.select(DDL_FACT_COLS)

print(f'\nLoading fact_supply_resilience...')
print(f'  Shape  : {sdf_fact_load.count()} baris x {len(sdf_fact_load.columns)} kolom')
print(f'  Kolom  : {sdf_fact_load.columns}\n')

sdf_fact_load.write \
    .format("jdbc") \
    .option("url",      DW_JDBC_URL) \
    .option("dbtable",  "public.fact_supply_resilience") \
    .option("user",     PG_USER) \
    .option("password", PG_PASS) \
    .option("driver",   "org.postgresql.Driver") \
    .option("batchsize","200") \
    .mode("append") \
    .save()

n = spark.read \
    .format("jdbc") \
    .option("url",     DW_JDBC_URL) \
    .option("dbtable", "(SELECT COUNT(*) AS n FROM public.fact_supply_resilience) t") \
    .option("user",    PG_USER) \
    .option("password",PG_PASS) \
    .option("driver",  "org.postgresql.Driver") \
    .load() \
    .collect()[0]['n']

print(f'  OK   fact_supply_resilience     -> {n:>5} baris tersimpan')
print('\nOK   Fact table berhasil di-load ke Data Warehouse!')


# VALIDASI POST-LOAD

def jdbc_query(sql: str):
    """Baca hasil SQL query dari DW via Spark JDBC."""
    return spark.read \
        .format("jdbc") \
        .option("url",      DW_JDBC_URL) \
        .option("dbtable",  f"({sql}) t") \
        .option("user",     PG_USER) \
        .option("password", PG_PASS) \
        .option("driver",   "org.postgresql.Driver") \
        .load()


print('=' * 65)
print('  VALIDASI POST-LOAD')
print('=' * 65)

print('\n-- [1] Row Count per Tabel --')
for tbl in ['dim_prov','dim_komoditas','dim_waktu','fact_supply_resilience']:
    n = jdbc_query(f'SELECT COUNT(*) AS n FROM public.{tbl}').collect()[0]['n']
    print(f'  - {tbl:<35} : {n:>5} baris')

print('\n-- [2] NULL check pada Foreign Key --')
for fk in ['prov_key','waktu_key','komoditas_key']:
    n = jdbc_query(
        f'SELECT COUNT(*) AS n FROM public.fact_supply_resilience WHERE {fk} IS NULL'
    ).collect()[0]['n']
    icon = 'OK  ' if n == 0 else 'FAIL'
    print(f'  {icon} fact.{fk:<28} : {n} NULL')

print('\n-- [3] Referential Integrity (SQL LEFT JOIN) --')
ri_checks = {
    'prov_key -> dim_prov': """
        SELECT COUNT(*) AS n FROM public.fact_supply_resilience f
        LEFT JOIN public.dim_prov p ON f.prov_key = p.prov_key
        WHERE p.prov_key IS NULL""",
    'waktu_key -> dim_waktu': """
        SELECT COUNT(*) AS n FROM public.fact_supply_resilience f
        LEFT JOIN public.dim_waktu w ON f.waktu_key = w.waktu_key
        WHERE w.waktu_key IS NULL""",
    'komoditas_key -> dim_komoditas': """
        SELECT COUNT(*) AS n FROM public.fact_supply_resilience f
        LEFT JOIN public.dim_komoditas k ON f.komoditas_key = k.komoditas_key
        WHERE k.komoditas_key IS NULL""",
}
for label, q in ri_checks.items():
    n = jdbc_query(q).collect()[0]['n']
    icon = 'OK  ' if n == 0 else 'FAIL'
    print(f'  {icon} {label:<38} : {n} orphan')

print('\n-- [4] Top 10 supply_risk_index Tertinggi --')
top10 = jdbc_query("""
    SELECT
        p.nama_provinsi,
        w.tahun,
        w.bulan,
        k.nama_komoditas,
        ROUND(f.supply_risk_index::NUMERIC, 6) AS supply_risk_index,
        f.sum_jumlah_sakit,
        f.populasi_ternak
    FROM public.fact_supply_resilience f
    JOIN public.dim_prov      p ON f.prov_key      = p.prov_key
    JOIN public.dim_waktu     w ON f.waktu_key     = w.waktu_key
    JOIN public.dim_komoditas k ON f.komoditas_key = k.komoditas_key
    ORDER BY f.supply_risk_index DESC
    LIMIT 10
""")
print()
top10.show(10, truncate=False)

print('-- [5] Statistik supply_risk_index --')
jdbc_query("""
    SELECT
        ROUND(MIN(supply_risk_index)::NUMERIC, 6)    AS min,
        ROUND(MAX(supply_risk_index)::NUMERIC, 6)    AS max,
        ROUND(AVG(supply_risk_index)::NUMERIC, 6)    AS mean,
        ROUND(STDDEV(supply_risk_index)::NUMERIC, 6) AS std
    FROM public.fact_supply_resilience
""").show(truncate=False)

print('=' * 65)
print('  OK   Validasi post-load SELESAI -- Data Warehouse siap digunakan.')


# RINGKASAN AKHIR & TUTUP SPARK
row = jdbc_query("""
    SELECT
        (SELECT COUNT(*) FROM public.dim_prov)               AS n_dim_prov,
        (SELECT COUNT(*) FROM public.dim_komoditas)          AS n_dim_komoditas,
        (SELECT COUNT(*) FROM public.dim_waktu)              AS n_dim_waktu,
        (SELECT COUNT(*) FROM public.fact_supply_resilience) AS n_fact,
        (SELECT ROUND(MIN(supply_risk_index)::NUMERIC,6) FROM public.fact_supply_resilience) AS risk_min,
        (SELECT ROUND(MAX(supply_risk_index)::NUMERIC,6) FROM public.fact_supply_resilience) AS risk_max,
        (SELECT ROUND(AVG(supply_risk_index)::NUMERIC,6) FROM public.fact_supply_resilience) AS risk_avg
""").collect()[0]

print(f"""
{'='*65}
  RINGKASAN FASE LOAD
{'='*65}
  Target DW    : postgresql://{PG_HOST}:{PG_PORT}/{DW_DB}

  Tabel Dimensi:
    dim_prov               : {row['n_dim_prov']:>5} baris
    dim_komoditas          : {row['n_dim_komoditas']:>5} baris
    dim_waktu              : {row['n_dim_waktu']:>5} baris

  Tabel Fakta:
    fact_supply_resilience : {row['n_fact']:>5} baris
      supply_risk_index min : {row['risk_min']}
      supply_risk_index max : {row['risk_max']}
      supply_risk_index avg : {row['risk_avg']}

  OK   ETL Pipeline selesai!
       Extract -> Transform -> Load
{'='*65}
""")

spark.stop()
print('  SparkSession ditutup.')