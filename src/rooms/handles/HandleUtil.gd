## 手柄可视化共享工具：椭圆阴影等绘制辅助（编辑器手柄 & 运行期武器阴影共用）。
class_name HandleUtil
extends Object

## 单位圆 12 边形顶点（用于近似椭圆/圆阴影）。
static func ellipse_poly(segments: int = 12) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(Vector2(cos(a), sin(a)))
	return pts

## 半透明黑色椭圆阴影 Polygon2D。size = (宽, 高) 倍率（单位圆×倍率）。
static func shadow_polygon(size: Vector2, alpha: float = 0.28) -> Polygon2D:
	var p := Polygon2D.new()
	p.polygon = ellipse_poly()
	p.scale = size
	p.color = Color(0, 0, 0, alpha)
	return p
