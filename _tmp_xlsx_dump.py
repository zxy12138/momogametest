# -*- coding: utf-8 -*-
import zipfile, re, json, os
from xml.etree import ElementTree as ET

XLSX = r"E:\Godot\Godot_Project\momogametest\DevelopmentRequirements\梦境逐影_美术素材清单_最终版.xlsx"
NS = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'

def col_to_idx(ref):
    m = re.match(r'([A-Z]+)(\d+)', ref)
    col = m.group(1); row = int(m.group(2))
    c = 0
    for ch in col: c = c*26 + (ord(ch)-64)
    return c-1, row

z = zipfile.ZipFile(XLSX)
names = z.namelist()
# shared strings
shared = []
if 'xl/sharedStrings.xml' in names:
    root = ET.fromstring(z.read('xl/sharedStrings.xml'))
    for si in root.findall(NS+'si'):
        # concat all <t> under si (handle rich text)
        txt = ''.join(t.text or '' for t in si.iter(NS+'t'))
        shared.append(txt)

# workbook sheet order + names
wb = ET.fromstring(z.read('xl/workbook.xml'))
rels = ET.fromstring(z.read('xl/_rels/workbook.xml.rels'))
rid_target = {}
for rel in rels:
    rid_target[rel.get('Id')] = rel.get('Target')
sheet_order = []
for sh in wb.find(NS+'sheets'):
    nm = sh.get('name'); rid = sh.get('{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id')
    tgt = rid_target.get(rid, '')
    tgt = tgt.lstrip('/').replace('\\','/')
    parts = [p for p in tgt.split('/') if p]
    if parts and parts[0] == 'xl':
        tgt = '/'.join(parts)
    else:
        tgt = 'xl/' + '/'.join(parts)
    sheet_order.append((nm, tgt))
print("NAMELIST sample:", [n for n in names if 'sheet' in n or 'sharedStrings' in n])
print("RESOLVED:", sheet_order)

CODE = re.compile(r'^[A-Za-z]+-\d+$')

out = []
for sname, stgt in sheet_order:
    data = z.read(stgt)
    root = ET.fromstring(data)
    rows = root.find(NS+'sheetData')
    grid = {}  # (col,row)->value
    maxcol = 0; maxrow = 0
    for row in rows.findall(NS+'row'):
        for c in row.findall(NS+'c'):
            ref = c.get('r'); t = c.get('t')
            ci, ri = col_to_idx(ref)
            maxcol = max(maxcol, ci); maxrow = max(maxrow, ri)
            v = None
            if t == 's':
                v = shared[int(c.find(NS+'v').text)]
            elif t == 'inlineStr':
                tnode = c.find(NS+'is')
                v = ''.join(x.text or '' for x in tnode.iter(NS+'t')) if tnode is not None else ''
            else:
                vn = c.find(NS+'v')
                v = vn.text if vn is not None else ''
            grid[(ci,ri)] = v
    out.append((sname, grid, maxcol, maxrow))

with open(r'E:\Godot\Godot_Project\momogametest\_tmp_xlsx_dump.txt','w',encoding='utf-8') as fo:
    for sname, grid, mc, mr in out:
        fo.write("\n========== SHEET: %s (cols=%d rows=%d) ==========\n" % (sname, mc+1, mr+1))
        # header
        hdr = [grid.get((c,1),'') for c in range(mc+1)]
        fo.write("HEADER: " + " | ".join(str(h) for h in hdr) + "\n")
        for r in range(2, mr+1):
            vals = [grid.get((c,r),'') for c in range(mc+1)]
            # skip fully empty rows
            if all(v=='' for v in vals): continue
            # detect code cell
            code = ''
            for v in vals:
                if isinstance(v,str) and CODE.match(v.strip()):
                    code = v.strip(); break
            if code:
                fo.write("%s :: %s\n" % (code, " | ".join(str(x) for x in vals)))
            else:
                fo.write("? :: " + " | ".join(str(x) for x in vals) + "\n")
print("dumped to _tmp_xlsx_dump.txt; sheets:", [s[0] for s in out])
