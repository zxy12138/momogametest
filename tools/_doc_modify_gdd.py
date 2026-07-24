"""修改梦境逐影_游戏设计文档_最终版.docx —— v4.0 预制整图方案

变更：
1. §9.1 场景结构表：RoomManager.gd 行重写（预制整图加载 + 空气墙 + 门），新增 Door / InvisibleWall 两行
2. §4.3 末尾新增预制整图方案说明段（含 changjing1.png 引用）
3. §7.2/7.3/7.4 场景概念段落后各新增「场景构建方式」说明段

保留原表格样式（Arial 20号字、CCCCC边框、白底），新增段落用默认正文样式。
"""
import zipfile, shutil, os, copy
from xml.etree import ElementTree as ET

SRC = 'DevelopmentRequirements/梦境逐影_游戏设计文档_最终版.docx'
TMP = '_tmp_gdd_new.docx'
NS  = '{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
NSW = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'

# 注册命名空间（避免 ns0: 前缀）
ET.register_namespace('', NSW)
ET.register_namespace('w',  NSW)
ET.register_namespace('w14','http://schemas.microsoft.com/office/word/2010/wordml')

def text_of(p):
    return ''.join((t.text or '') for t in p.iter(NS+'t'))

def make_paragraph(text, style=None):
    """生成一个新段落（默认正文样式）"""
    p = ET.Element(NS+'p')
    r = ET.SubElement(p, NS+'r')
    if style:
        rPr = ET.SubElement(r, NS+'rPr')
        rFonts = ET.SubElement(rPr, NS+'rFonts')
        for k in ('ascii','hAnsi','eastAsia','cs'):
            rFonts.set(NS+k, 'Arial')
        sz = ET.SubElement(rPr, NS+'sz'); sz.set(NS+'val','20')
        szCs = ET.SubElement(rPr, NS+'szCs'); szCs.set(NS+'val','20')
    t = ET.SubElement(r, NS+'t')
    t.text = text
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    return p

def clone_row_template(template_row, col1, col2):
    """克隆表格行模板（保留 tcPr/borders/shading），只改两个单元格的文本"""
    new_row = copy.deepcopy(template_row)
    cells = list(new_row.iter(NS+'tc'))
    # 第一格：场景/脚本名；第二格：用途
    for i, txt in enumerate([col1, col2]):
        tc = cells[i]
        # 移除所有段落
        for p in list(tc.iter(NS+'p')):
            tc.remove(p)
        # 加新段落
        p = make_paragraph(txt, style=True)
        tc.append(p)
    return new_row

# ---- 主流程 ----
shutil.copyfile(SRC, TMP)
with zipfile.ZipFile(TMP, 'r') as z:
    files = {n: z.read(n) for n in z.namelist()}

xml_bytes = files['word/document.xml']
root = ET.fromstring(xml_bytes)
body = root.find(NS+'body')

# === 1) §9.1 场景结构表（tbl#18）修改 ===
tbls = list(root.iter(NS+'tbl'))
tbl18 = tbls[18]
rows = list(tbl18.iter(NS+'tr'))

# Row index 5 = RoomManager.gd
row5 = rows[5]
cells5 = list(row5.iter(NS+'tc'))
# 改用途
for p in list(cells5[1].iter(NS+'p')):
    cells5[1].remove(p)
cells5[1].append(make_paragraph(
    '加载预制场景整图作为房间背景；按配置在其上叠加「不可见空气墙」划定可走/不可走区域；在门位置放置带开/关动画的门节点；管理怪物刷新（body_exited 信号监听）。',
    style=True
))

# 克隆 row5 作为模板，生成 Door 与 InvisibleWall 两行
new_door = clone_row_template(row5,
    'Door.tscn / Door.gd',
    '门的开关动画节点：根据房间状态切换门的精灵帧（关闭态 / 开启动画 4 帧），控制对应 Area2D 触发器是否可激活。')
new_wall = clone_row_template(row5,
    'InvisibleWall.tscn',
    '「空气墙」碰撞体：纯 StaticBody2D + CollisionShape2D，无任何可见贴图，仅用于在预制整图上定义不可穿越区域（墙体、家具轮廓、地图边界等）。')

# 在 row5 后面插入新行（用 Element.insert 在 row5 的父 tbl 中找位置）
tbl18_children = list(tbl18)
# row5 在 tbl18_children 中的索引
row5_idx = tbl18_children.index(row5)
tbl18.insert(row5_idx + 1, new_door)
tbl18.insert(row5_idx + 2, new_wall)

# === 2) §4.3 末尾插入预制整图方案说明段 ===
paras = list(root.iter(NS+'p'))
for i, p in enumerate(paras):
    if 'CanvasLayer，快捷键 M 或 Tab' in text_of(p):
        new_p = make_paragraph(
            '场景视觉呈现：每种房间类型的视觉由美术预制整图提供（PNG），RoomManager 加载该图作为背景，在其上叠加「不可见空气墙」划定可走/不可走区域，并在门位置放置带开/关动画的门精灵。参考样图：assets/tiles/changjing1.png（第一层办公室类型）。',
            style=True
        )
        parent = p.getparent() if hasattr(p, 'getparent') else None
        # stdlib ET 没有 getparent；通过 idx_of_in_body 间接定位
        body_children = list(body)
        idx = body_children.index(p)
        body.insert(idx + 1, new_p)
        break

# === 3) §7.2 / 7.3 / 7.4 场景概念段后插入「场景构建方式」说明 ===
SCENE_NOTES = {
    '凌晨的写字楼': '【场景构建方式】本层场景采用「预制整图」方案：每种房间类型由美术提供一张完整的俯视像素图（墙/地板/家具/灯光/散落物全部烘焙在一起）。参考样图：assets/tiles/changjing1.png。RoomManager 加载该图作为背景，在其上叠加不可见空气墙与门节点。',
    '地铁站、人行道': '【场景构建方式】本层场景采用「预制整图」方案：每种房间类型由美术提供一张完整的俯视像素图（地铁站/街道/旋转门等元素全部烘焙）。RoomManager 加载该图作为背景，在其上叠加不可见空气墙与门节点。',
    '所有噩梦的来源': '【场景构建方式】本层场景采用「预制整图」方案：每种房间类型由美术提供一张完整的俯视像素图（纯黑底色+红色紫色投影+未读消息墙等元素全部烘焙）。RoomManager 加载该图作为背景，在其上叠加不可见空气墙与门节点。',
}
inserted = set()
for p in list(root.iter(NS+'p')):
    txt = text_of(p)
    for key, note in SCENE_NOTES.items():
        if key in txt and key not in inserted:
            new_p = make_paragraph(note, style=True)
            body_children = list(body)
            idx = body_children.index(p)
            body.insert(idx + 1, new_p)
            inserted.add(key)
            break

# 写出
new_xml = ET.tostring(root, encoding='UTF-8')
if not new_xml.startswith(b'<?xml'):
    new_xml = b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + new_xml
files['word/document.xml'] = new_xml

# 写回新 docx（保持原文件结构）
with zipfile.ZipFile(SRC, 'w', zipfile.ZIP_DEFLATED) as zout:
    for name, data in files.items():
        zout.writestr(name, data)

os.remove(TMP)
print('GDD 修改完成')
print('  §9.1: RoomManager 行已重写，新增 Door + InvisibleWall 行')
print(f'  §4.3 末尾新增段、§7.2/7.3/7.4 各新增段：{inserted}')