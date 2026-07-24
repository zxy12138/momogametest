"""修改梦境逐影_美术素材清单_最终版.xlsx —— v4.0 预制整图方案

Sheet3 重构为 5 段：场景整图 / 门动画 / 驿站内饰 / 通用道具 / 地图节点
+ 废弃清单（通用 Tileset T-000/T-001/T-020~T-044 标注为「已废弃·改用预制整图」）

Sheet6 总览行同步：Tileset 行改名「场景整图」+「门动画」。
"""
import zipfile, os, copy, shutil
from xml.etree import ElementTree as ET

SRC = 'DevelopmentRequirements/梦境逐影_美术素材清单_最终版.xlsx'
TMP = '_tmp_xlsx_new.xlsx'
NSW = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
NS  = '{' + NSW + '}'
ET.register_namespace('', NSW)

# ---- 单元格构造 ----
def cell(text, style_idx=None, row=None, col=None):
    """inlineStr 单元格"""
    c = ET.Element(NS+'c')
    if style_idx is not None:
        c.set(NS+'s', str(style_idx))
    c.set(NS+'t', 'inlineStr')
    is_ = ET.SubElement(c, NS+'is')
    t = ET.SubElement(is_, NS+'t')
    t.text = text if text is not None else ''
    t.set('{http://www.w3.org/XML/1998/namespace}space', 'preserve')
    return c

def row(*texts, style_idx=None):
    """构造一行（每列一个 inlineStr 单元格）"""
    r = ET.Element(NS+'row')
    for txt in texts:
        r.append(cell(txt, style_idx=style_idx))
    return r

# ============= Sheet3 完整新内容 =============
SHEET3_ROWS = []

# 标题与说明
SHEET3_ROWS.append(row('🗺️ 场景 · 社畜梦境 · 预制整图与门动画（v4.0）'))
SHEET3_ROWS.append(row(
    '【v4.0 方案变更】通用 Tileset (T-000/T-001/T-020~T-044) 已废弃；'
    '场景由美术预制整图提供（一图一房，含墙/地板/家具/灯光全部烘焙）。'
    '参考样图：assets/tiles/changjing1.png（第一层办公室类型）。'
    '工程只需实现「门的开关动画」与「空气墙（InvisibleWall）」的逻辑。'
))
# 表头
SHEET3_ROWS.append(row('编号', '素材名称', '英文名称', '类型', '尺寸(px)', '帧数', '说明', '所属层', '完成状态'))

# === A. 场景整图（Scene Backgrounds）===
SHEET3_ROWS.append(row('━━━ A. 场景整图（Scene Backgrounds） ━━━'))
SCENE_BG = [
    # (编号, 名称, 英文, 类型, 尺寸, 帧数, 说明, 所属层, 状态)
    ('S-001', '办公室·战斗房',   'Office Combat Room BG',     '场景整图', '960×540', '1张', '凌晨办公室，工位林立，散落文件。参考样图：changjing1.png',          '第一层', '□'),
    ('S-002', '办公室·精英房',   'Office Elite Room BG',      '场景整图', '960×540', '1张', '办公室·深度，灯光更昏暗，文件堆积更多',                             '第一层', '□'),
    ('S-003', '办公室·驿站房',   'Office Rest Stop BG',       '场景整图', '960×540', '1张', '24小时便利店风内景，暖光，安全区',                                  '第一层', '□'),
    ('S-004', '办公室·神秘房',   'Office Mystery Room BG',    '场景整图', '960×540', '1张', '办公室·变体，全屏红光警告，NPC 散乱',                              '第一层', '□'),
    ('S-005', '办公室·Boss房',   'Office Boss Room BG',       '场景整图', '960×540', '1张', '大型会议室/总监办公室，巨大窗户，城市夜景',                        '第一层', '□'),
    ('S-006', '办公室·传送阵房', 'Office Transition Room BG', '场景整图', '960×540', '1张', '电梯大厅，传送门标记地板',                                          '第一层', '□'),
    ('S-007', '通勤·战斗房',     'Commute Combat Room BG',    '场景整图', '960×540', '1张', '地铁站月台，候车椅，轨道',                                          '第二层', '□'),
    ('S-008', '通勤·精英房',     'Commute Elite Room BG',     '场景整图', '960×540', '1张', '拥挤街道，电瓶车/快递箱障碍物',                                     '第二层', '□'),
    ('S-009', '通勤·驿站房',     'Commute Rest Stop BG',      '场景整图', '960×540', '1张', '深夜便利店/自动售货机区域，暖光',                                   '第二层', '□'),
    ('S-010', '通勤·神秘房',     'Commute Mystery Room BG',   '场景整图', '960×540', '1张', '逆向扶梯/旋转门陷阱区域',                                           '第二层', '□'),
    ('S-011', '通勤·Boss房',     'Commute Boss Room BG',      '场景整图', '960×540', '1张', '无尽延伸的地铁车厢内部',                                            '第二层', '□'),
    ('S-012', '通勤·传送阵房',   'Commute Transition Room BG','场景整图', '960×540', '1张', '地铁出口/路标，指向不存在',                                         '第二层', '□'),
    ('S-013', '崩溃·战斗房',     'Breakdown Combat Room BG',  '场景整图', '960×540', '1张', '纯黑底+红色未读消息投影墙',                                         '第三层', '□'),
    ('S-014', '崩溃·精英房',     'Breakdown Elite Room BG',   '场景整图', '960×540', '1张', '逾期任务板墙面，DDL 倒计时跳动',                                    '第三层', '□'),
    ('S-015', '崩溃·驿站房',     'Breakdown Rest Stop BG',    '场景整图', '960×540', '1张', '安静的便利店，唯一亮着的暖光',                                      '第三层', '□'),
    ('S-016', '崩溃·神秘房',     'Breakdown Mystery Room BG', '场景整图', '960×540', '1张', '扭曲几何边框，花屏投影',                                            '第三层', '□'),
    ('S-017', '崩溃·Boss房',     'Breakdown Boss Room BG',    '场景整图', '960×540', '1张', '单人办公室+巨大待办清单投影，无窗，黑色虚空',                      '第三层', '□'),
    ('S-018', '崩溃·传送阵房',   'Breakdown Transition Room BG','场景整图','960×540','1张', '升向出口的「楼梯」，通往宁静',                                      '第三层', '□'),
]
for r in SCENE_BG: SHEET3_ROWS.append(row(*r))

# === B. 门动画（Door Animations）===
SHEET3_ROWS.append(row('━━━ B. 门动画（Door Animations） ━━━'))
DOOR_ROWS = [
    ('D-001', '标准门·关闭态',  'Door Standard Closed',  '门精灵',  '48×64',  '1帧',  '金属电子门关闭态，按房间状态切换贴图',                                  '全层通用', '□'),
    ('D-002', '标准门·开启动画','Door Standard Open',    '门精灵',  '48×64',  '4帧',  '滑开消散动画（横向精灵表 192×64）',                                    '全层通用', '□'),
    ('D-003', 'Boss 门·特殊态', 'Door Boss Special',     '门精灵',  '64×80',  '2帧',  'Boss 房专用门，红色警示+封印纹路，破关后切开启',                        '全层通用', '□'),
]
for r in DOOR_ROWS: SHEET3_ROWS.append(row(*r))

# === C. 驿站内饰（Rest Stop Interior）===
SHEET3_ROWS.append(row('━━━ C. 驿站内饰（Rest Stop Interior） ━━━'))
REST_ROWS = [
    ('I-001', '梦境驿站·内景',     'Dream Rest Stop Interior',     '场景', '320×180', '1张', '24小时便利店风，暖光，安全感（沿用自 v3 T-050）',                                  '驿站', '□'),
    ('I-002', '便利店柜台',         'Convenience Store Counter',    '场景道具', '48×32', '1帧', '便利店收银台（驿站商店，沿用自 v3 T-051）',                                          '驿站', '□'),
    ('I-003', '回复点·热水杯',     'Heal Point Hot Cup',           '场景道具/动画', '16×24', '4帧', '冒热气的杯子，点击回血（沿用自 v3 T-052）',                                          '驿站', '□'),
]
for r in REST_ROWS: SHEET3_ROWS.append(row(*r))

# === D. 通用道具（Common Props）===
SHEET3_ROWS.append(row('━━━ D. 通用道具（Common Props） ━━━'))
PROP_ROWS = [
    ('P-001', '梦境传送阵',         'Dream Teleport Circle',  '道具/特效', '48×16', '4帧', '旋转光圈在地板（沿用自 v3 T-004）',  '全层通用', '□'),
    ('P-002', '宝箱·关闭',         'Treasure Chest Closed',  '道具',     '16×16', '1帧', '文件夹造型宝箱，社畜风（沿用自 v3 T-005）', '全层通用', '□'),
    ('P-003', '宝箱·开启动画',     'Treasure Chest Open',    '道具',     '16×16', '5帧', '文件夹翻开散出星光（沿用自 v3 T-006）',     '全层通用', '□'),
]
for r in PROP_ROWS: SHEET3_ROWS.append(row(*r))

# === E. 地图节点（Map Node Icons）===
SHEET3_ROWS.append(row('━━━ E. 地图节点（Map Node Icons） ━━━'))
MAP_ROWS = [
    ('N-001', '地图节点·战斗房间',       'Map Node Combat Room',     '地图UI', '24×24', '1帧', '剑图标',                                    '地图UI', '□'),
    ('N-002', '地图节点·精英房间',       'Map Node Elite Room',      '地图UI', '24×24', '1帧', '骷髅图标',                                  '地图UI', '□'),
    ('N-003', '地图节点·驿站',           'Map Node Rest Stop',       '地图UI', '24×24', '1帧', '茶杯图标',                                  '地图UI', '□'),
    ('N-004', '地图节点·神秘房间',       'Map Node Mystery Room',    '地图UI', '24×24', '1帧', '问号图标',                                  '地图UI', '□'),
    ('N-005', '地图节点·Boss房间',       'Map Node Boss Room',       '地图UI', '24×24', '1帧', '皇冠图标',                                  '地图UI', '□'),
    ('N-006', '地图节点·已访问(暗色)',  'Map Node Visited Dim',     '地图UI', '24×24', '1帧', '各类型图标的灰色版',                       '地图UI', '□'),
    ('N-007', '地图节点·锁定(灰轮廓)',  'Map Node Locked Outline',  '地图UI', '24×24', '1帧', '锁图标+灰色轮廓',                          '地图UI', '□'),
    ('N-008', '地图节点·Lv21感知轮廓', 'Map Node Sensed Outline',  '地图UI', '24×24', '1帧', '半透明显示类型但仍锁定',                  '地图UI', '□'),
    ('N-009', '地图·当前位置标记',       'Map Current Position',     '地图UI', '16×16', '3帧', '弥绘头像小图标闪烁',                       '地图UI', '□'),
    ('N-010', '地图·房间连线',           'Map Room Connector Line',  '地图UI', '像素线段', 'N/A', '虚线路径，已访问段高亮',                  '地图UI', '□'),
]
for r in MAP_ROWS: SHEET3_ROWS.append(row(*r))

# === F. 已废弃清单（Deprecated v3.0 Tileset）===
SHEET3_ROWS.append(row('━━━ F. 已废弃清单（v3.0 通用 Tileset 已被预制整图方案取代） ━━━'))
DEP_ROWS = [
    ('T-000', '通用地板·梦境基础',     'Base Dream Floor Tile',      'Tileset·废弃', '16×16', '8块', '已废弃：改用 S-xxx 整图方案',                              '—', '✗'),
    ('T-001', '通用墙壁',              'Base Wall Tile',             'Tileset·废弃', '16×16', '8块', '已废弃：改用 InvisibleWall 空气墙',                        '—', '✗'),
    ('T-020', '办公室地板·瓷砖',       'Office Floor Tile',          'Tileset·废弃', '16×16', '8块', '已废弃：地板烘焙进 S-001~S-006',                           '—', '✗'),
    ('T-021', '办公室墙壁',            'Office Wall Tile',           'Tileset·废弃', '16×16', '8块', '已废弃：墙烘焙进 S-001~S-006',                             '—', '✗'),
    ('T-022', '荧光灯·闪烁装饰',       'Flickering Fluorescent Light','Tileset·废弃','32×8', '3帧',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-023', '工位桌堆文件装饰',      'Cubicle Desk Clutter',       'Tileset·废弃', '32×24','3种',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-024', '卡纸打印机装饰物',      'Printer Prop Decor',         'Tileset·废弃', '24×24','1种',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-025', '第一层远景背景',         'Layer1 Background Far',      'Tileset·废弃', '320×180','1张','已废弃：远景烘焙进场景整图',                              '—', '✗'),
    ('T-026', '红色警告灯闪烁',         'Red Warning Light Blink',    'Tileset·废弃', '8×8',  '2帧',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-030', '地铁站地板·月台',       'Subway Platform Floor',      'Tileset·废弃', '16×16','8块',  '已废弃：地板烘焙进 S-007~S-012',                          '—', '✗'),
    ('T-031', '地铁站墙壁',            'Subway Wall Tile',           'Tileset·废弃', '16×16','8块',  '已废弃：墙烘焙进 S-007~S-012',                            '—', '✗'),
    ('T-032', '轨道装饰',              'Rail Track Tile',            'Tileset·废弃', '16×8', '4块',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-033', '路灯装饰(街道段)',      'Street Lamp Decor',          'Tileset·废弃', '8×32', '2帧',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-034', '旋转门装饰',            'Revolving Door Decor',       'Tileset·废弃', '32×48','1种',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-035', '第二层远景背景',         'Layer2 Background Far',      'Tileset·废弃', '320×180','1张','已废弃：远景烘焙进场景整图',                              '—', '✗'),
    ('T-036', '霓虹绿指示牌',           'Neon Green Sign',            'Tileset·废弃', '32×12','1帧',  '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-040', '深渊几何地板',          'Abyss Geometric Floor',      'Tileset·废弃', '16×16','8块',  '已废弃：地板烘焙进 S-013~S-018',                          '—', '✗'),
    ('T-041', '扭曲墙壁(会动)',         'Warped Wall (Animated)',     'Tileset·废弃', '16×16','4帧',  '已废弃：墙烘焙进 S-013~S-018',                            '—', '✗'),
    ('T-042', '投影消息墙',            'Projected Message Wall',     'Tileset·废弃', '64×48','动态', '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-043', 'DDL倒计时牌',            'Deadline Countdown Sign',    'Tileset·废弃', '48×24','动态', '已废弃：装饰烘焙进场景整图',                              '—', '✗'),
    ('T-044', '第三层背景粒子',         'Layer3 Background Particles','Tileset·废弃', '320×180','动态','已废弃：装饰烘焙进场景整图',                              '—', '✗'),
]
for r in DEP_ROWS: SHEET3_ROWS.append(row(*r))

# ============= Sheet6 总览行更新 =============
SHEET6_ROWS = []
SHEET6_ROWS.append(row('📊 素材总览 · 优先级追踪（v4.0）'))
SHEET6_ROWS.append(row('类别', '英文类别', '总数', '优先级', '是否新增/变更', '关键说明', '完成状态'))
OVERVIEW = [
    ('主角弥绘动画（含真形/庆生）', 'Player Miai Animations', '10套', '★★★★★', '原有', '游戏启动首要完成', '□'),
    ('武器姿态叠加层',                'Weapon Pose Overlays',    '3套', '★★★★★', '原有', '与主角动画绑定', '□'),
    ('武器图标（全9种+升阶3种）',     'Weapon Icons (9+3)',     '12个','★★★★★', '原有', '开始选武器时需要', '□'),
    ('弹射物',                       'Projectiles',             '6种','★★★★★', '原有', '与武器同步', '□'),
    ('暴击专属特效（橙色爆光/数字）','Crit FX (Flash/Number)',  '3种','★★★★★', '原有', '核心系统，早期实现', '□'),
    ('第一层怪物·午夜办公室（含Boss）','Layer1 Monsters & Boss','13套','★★★★★','尺寸已更新，Boss为260×500','第一层通关必需','□'),
    ('第二层怪物·无尽通勤路（含Boss）','Layer2 Monsters & Boss','12套','★★★★☆','尺寸已更新，Boss为260×500','第二层解锁后','□'),
    ('第三层怪物·深夜崩溃核心（含Boss）','Layer3 Monsters & Boss','11套','★★★☆☆','尺寸已更新，Boss为260×500','最终Boss最后制作','□'),
    ('🆕 场景整图·第一层（办公室，6房）','Layer1 Scene BG (Office)','6张','★★★★★','v4.0 新增（取代 v3 通用 Tileset）','参考样图 changjing1.png','□'),
    ('🆕 场景整图·第二层（通勤，6房）', 'Layer2 Scene BG (Commute)','6张','★★★★☆','v4.0 新增', '第二层才用','□'),
    ('🆕 场景整图·第三层（崩溃，6房）', 'Layer3 Scene BG (Breakdown)','6张','★★★☆☆','v4.0 新增','最终Boss最后制作','□'),
    ('🆕 门动画（关闭+开启+Boss门）',  'Door Animations',         '3套','★★★★★','v4.0 新增','门开/关帧动画 + Area2D 触发器控制','□'),
    ('网状地图节点图标（5种+状态变化）','Map Node Icons',         '10种','★★★★★','编号改为 N-001~N-010','地图系统核心','□'),
    ('地图UI界面（传送弹窗/图例等）',  'Map UI (Popup/Legend)',   '4件','★★★★★','原有','与地图节点配套','□'),
    ('驿站·便利店内景+柜台+热水杯',     'Rest Stop Interior',     '3套','★★★★☆','编号改为 I-001~I-003','安全区素材','□'),
    ('通用道具（传送阵/宝箱）',         'Common Props (P-001~P-003)','3套','★★★★★','编号改为 P-001~P-003','基础玩法必需','□'),
    ('房间怪物刷新特效',               'Room Respawn FX',         '1种','★★★★☆','原有','体现魂类机制','□'),
    ('刷新音效',                       'Respawn SFX',             '1个','★★★★☆','原有','刷新时音效反馈','□'),
    ('死亡CG（自制，3张死亡+1生日）',  'Death CG (3+1)',          '4张','★★★★☆','原有·自制项','内容自制，流程UI先做','□'),
    ('死亡流程UI（遮罩/提示/重来界面）','Death Flow UI',           '9件','★★★★★','原有','死亡体验核心','□'),
    ('死亡/重来相关音效',              'Death/Retry SFX',         '3个','★★★★☆','原有','死亡氛围','□'),
    ('战斗HUD（含暴击率显示）',        'Combat HUD',              '11件','★★★★★','原有','游戏开始就需要','□'),
    ('主菜单/按钮/通用UI',             'Main Menu & Common UI',   '6件','★★★★☆','原有','可用占位临时代替','□'),
    ('武器选择界面',                    'Weapon Select UI',        '3件','★★★★★','原有','开场选武器就需要','□'),
    ('词条系统UI',                      'Trait System UI',         '3件','★★★★☆','原有','核心系统配套','□'),
    ('暴击伤害橙色字体',                'Crit Damage Font',        '1套','★★★★★','原有','区分普通/暴击伤害','□'),
    ('BGM（9首）',                      'BGM (9 Tracks)',          '9首','★★★★☆','原有','可先用免费素材占位','□'),
    ('SFX音效（32个）',                 'SFX (32 Sounds)',         '32个','★★★★☆','原有','可用免费素材占位','□'),
]
for r in OVERVIEW: SHEET6_ROWS.append(row(*r))
SHEET6_ROWS.append(row(
    '🆕 v4.0 更新：场景构建方案从「v3.0 通用 Tileset 平铺」改为「预制整图 + 空气墙 + 门动画」。'
    'Sheet3 中 T-000/T-001/T-020~T-044 标记为废弃；新增 S-001~S-018（3层 × 6 房型）整图、D-001~D-003 门动画、'
    'I-001~I-003 驿站内饰、P-001~P-003 通用道具、N-001~N-010 地图节点。'
    '工程只负责「门开/关动画」与「InvisibleWall 空气墙」逻辑；场景视觉由美术预制整图提供。'
    '参考样图：assets/tiles/changjing1.png。'
))

# ============= 写回 xlsx =============
# SRC 当前被 WPS 占用，无法直接覆盖。改策略：保留 SRC 不动，
# 把 v4.0 内容写到 sibling 文件 _梦境逐影_美术素材清单_最终版_v4.0.xlsx，
# 由用户关闭 WPS 后手动替换（或拷贝覆盖）。

# 先读源文件结构（注意：SRC 可读不能写，但 zipfile.ZipFile 只读打开 OK）
TMP_READ = '_tmp_read.xlsx'
shutil.copyfile(SRC, TMP_READ)
with zipfile.ZipFile(TMP_READ, 'r') as z:
    files = {n: z.read(n) for n in z.namelist()}
os.remove(TMP_READ)

def rebuild_sheet(files, sheet_filename, new_rows):
    """替换指定 sheet 的全部 row 元素（保留 sheet 顶层结构如 dimension/cols/sheetData）"""
    xml = files[sheet_filename].decode('utf-8')
    root = ET.fromstring(xml)
    # OOXML: <row> 是 <sheetData> 的子元素，不是 worksheet 直接子元素
    sd = root.find(NS+'sheetData')
    if sd is None:
        raise RuntimeError(f'{sheet_filename}: 找不到 <sheetData>')
    # 清空 sheetData 内所有 row
    for child in list(sd):
        if child.tag == NS+'row':
            sd.remove(child)
    # 把新 row 加到 sheetData
    for r in new_rows:
        sd.append(r)
    files[sheet_filename] = b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n' + ET.tostring(root, encoding='UTF-8')

rebuild_sheet(files, 'xl/worksheets/sheet3.xml', SHEET3_ROWS)
rebuild_sheet(files, 'xl/worksheets/sheet6.xml', SHEET6_ROWS)

# 写到 sibling v4.0 文件
DST_V4 = os.path.join(os.path.dirname(SRC), '_梦境逐影_美术素材清单_最终版_v4.0.xlsx')
if os.path.exists(DST_V4):
    os.remove(DST_V4)
with zipfile.ZipFile(DST_V4, 'w', zipfile.ZIP_DEFLATED) as zout:
    for name, data in files.items():
        zout.writestr(name, data)

if os.path.exists(TMP):
    os.remove(TMP)
print(f'xlsx v4.0 内容已写出到 sibling 文件: {DST_V4}')
print(f'  路径: {DST_V4}')
print(f'  Sheet3 行数: {len(SHEET3_ROWS)}')
print(f'  Sheet6 行数: {len(SHEET6_ROWS)}')
print(f'  ★ 提示：原 SRC 仍被 WPS 占用，请关闭 WPS 后手动把 _v4.0.xlsx 改名覆盖原文件')