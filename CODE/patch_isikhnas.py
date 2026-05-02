import json

file_path = r'd:\STIS SEM 6\TPD\TPD UTS KELOMPOK 1\DATA\ISHIKNAS\ishiknas_generate_dummy.ipynb'
with open(file_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

for cell in data['cells']:
    if cell['cell_type'] == 'code' and any('data_sakit = []' in line for line in cell['source']):
        source = cell['source']
        for i, line in enumerate(source):
            if 'jumlah_gejala' in line and 'random.randint' in line:
                # Modifikasi baris jumlah_gejala agar diakhiri koma
                if not line.rstrip('\n').endswith(','):
                    source[i] = line.rstrip('\n') + ',\n'
                
                # Cek apakah jumlah_mati sudah ada
                if i + 1 >= len(source) or 'jumlah_mati' not in source[i+1]:
                    source.insert(i+1, '        "jumlah_mati": random.randint(0, 20)\n')
                break

with open(file_path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)

print("Patch iSIKHNAS berhasil!")
