import os
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.bash import BashOperator

# ─────────────────────────────────────────────────────────────
# PATH KONFIGURASI (Pemisahan WSL dan Windows)
# ─────────────────────────────────────────────────────────────

PYTHON_BIN = "/mnt/c/Users/anggi/Documents/KULIAH/TINGKAT 3/SEMESTER 6/TPD/PROJECT UTS/UTS-TPD-KELOMPOK-1/.venv/Scripts/python.exe"
CODE_DIR_WIN = r"C:\Users\anggi\Documents\KULIAH\TINGKAT 3\SEMESTER 6\TPD\PROJECT UTS\UTS-TPD-KELOMPOK-1\CODE"

# ─────────────────────────────────────────────────────────────
# DEFAULT ARGS
# ─────────────────────────────────────────────────────────────
default_args = {
    "owner":            "kelompok1_tpd",
    "depends_on_past":  False,
    "start_date":       datetime(2026, 5, 1),
    "retries":          1,
    "retry_delay":      timedelta(minutes=3),
    "email_on_failure": False,
}

# ─────────────────────────────────────────────────────────────
# DEFINISI DAG
# ─────────────────────────────────────────────────────────────
with DAG(
    dag_id="livestock_intelligence_etl_final",
    default_args=default_args,
    description="ETL Pipeline TPD Kelompok 1 (Extract, Transform, Load)",
    schedule='@daily',
    catchup=False,
    tags=["UTS", "TPD", "Kelompok1"],
) as dag:
    t_extract = BashOperator(
        task_id="fase_extract",
        bash_command=f'export PYTHONIOENCODING=utf-8 && "{PYTHON_BIN}" "{CODE_DIR_WIN}\\EXTRACT\\extract.py"',
    )

    t_transform = BashOperator(
        task_id="fase_transform",
        bash_command=f'export PYTHONIOENCODING=utf-8 && "{PYTHON_BIN}" "{CODE_DIR_WIN}\\TRANSFORM\\transform.py"',
    )

    t_load = BashOperator(
        task_id="fase_load",
        bash_command=f'export PYTHONIOENCODING=utf-8 && "{PYTHON_BIN}" "{CODE_DIR_WIN}\\LOAD\\load.py"',
    )

    # ── Dependency Graph ─────────────────────────────
    t_extract >> t_transform >> t_load