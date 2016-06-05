/** SVG $(LINK http://www.w3.org/TR/SVG/)のなんちゃって実装
 * Date:       2016-Jun-05 20:37:39
 * Authors:
 * License:

Description:
  o 一連の流れ
  $(OL
    $(LI SVGファイルを読み込む。(このモジュールでは扱いません。
        文字列インポートとか使ってね。))
    $(LI $(LINK #sworks.xml.AXML)へと変換する。)
    $(LI &lt;use&gt;要素の展開とか style の適用とか)
    $(LI $(LINK #sworks.svg.SVG)へと変換する。)
    $(LI $(LINK #sworks.svg.SVG)を、計算し易いように変換する。$(BR)
        サイズの変更や、パスの展開(曲線から直線の連続へ)。)
    $(LI 扱えない情報とかを落とした、描画し易い形式の
        $(LINK #sworks.svg.SVGPL)へと変換する。)
    $(LI ラスタライズ。はこのモジュールでは扱いません。
         →$(LINK #sworks.win32.svgr))
  )

Bugs:
  <del>dmd2.068.2</del>
  <del>CTFEで out of memory.</del>
   └→ $(LINK #sworks.base.matrix.ct_acos)の問題であることが判明。$(BR)
        dmd2.069現在は解消していますが、精度が落ちてます。$(BR)
        (小数点以下4ケタ程度の精度です。)
**/
module sworks.svg;

import sworks.base.matrix;
import sworks.base.ctfe;
import sworks.util.cached_buffer;
import sworks.xml;
debug import std.stdio;

/// SVG の名前空間識別名
enum SVG_URI = "http://www.w3.org/2000/svg";

/** SVG ファイルの最外殼を表す。&lt;svg&gt;に対応したデータを格納する。
 */
struct SVG
{
    ViewBox viewBox; ///
    AG[] g;    ///
}

/** viewBox属性の値を格納する。
 */
struct ViewBox
{
    float minX, minY, width, height;
    bool empty() @property const
    {
        import std.math : isNaN;
        return minX.isNaN || minY.isNaN || !(0 < width) || !(0 < height);
    }
}

/** 塗り潰しに関するルートクラス。

塗り潰しの種類を得る為に、このクラスからの実行時ダウンキャストを行う。
**/
abstract class AFill
{
    ///
    enum RULE
    {
        _DUMMY,
        NONZERO, ///
        EVENODD, ///
    }

    string id; ///
    float opacity; ///
    RULE rule; ///

    ///
    this(){}
    ///
    this(string i, float o, RULE r){ id = i; opacity = o; rule = r;}

    ///
    void transform(in ref Matrix3f){}
}

/** 塗らない。
 */
class NoFill : AFill
{ this(){ super(); } }

/** 単色で塗る。
 */
class Fill : AFill
{
    uint color; ///

    ///
    this(float o, RULE r, uint c) { super("", o, r); color = c; }
    ///
    this(string i, float o, RULE r, uint c) { super(i, o, r); color = c; }
}

/** グラデーションで塗る。
 */
class LinearGradient : AFill
{
    /** グラデーションの色の編集点を表す。
     */
    struct Stop
    {
        string id; ///
        uint color; ///
        float opacity = 1.0; ///
        float offset; /// [0, 1] の範囲。0 のときpos1、1のときpos2の位置となる。
    }
    Stop[] stops; ///
    Vector2f pos1 = Vector2f(float.nan);///
    Vector2f pos2 = Vector2f(float.nan); ///

    ///
    this(){ super(); }
    ///
    this(string i, float o, RULE r, Stop[] s, in Vector2f p1, in Vector2f p2)
    {
        super(i, o, r);
        stops = s;
        pos1 = p1;
        pos2 = p2;
    }

    override void transform(in ref Matrix3f mat)
    { pos1 = mat * pos1; pos2 = mat * pos2; }

    override string toString() const
    {
        import std.string : join;
        import std.conv : to;
        return ["LinearGradient(", pos1.to!string, ", ", pos2.to!string,
                ", ", stops.to!string, ")"].join;
    }
}

/** 円形グラデーション
 */
class RadialGradient : LinearGradient
{
    ///
    float radius;
    ///
    Matrix3f matrix;

    ///
    this(){ super(); }
    ///
    this(string i, float o, RULE r, Stop[] s, Vector2f p1, Vector2f p2,
         float rad, in Matrix3f t)
    {
        super(i, o, r, s, p1, p2);
        radius = rad;
        matrix = t;
    }

    override void transform(in ref Matrix3f mat)
    {
        super.transform(mat);
        radius *= mat[0];
        matrix = mat * matrix * mat.inverseMatrix;
    }
}


/** 線描に関するルートクラス

線の種類を得る為に、このクラスからの実行時ダウンキャストを行う。
**/
abstract class AStroke
{
    string id; ///
    ///
    enum LINECAP
    {
        _DUMMY,
        BUTT,  ///
        ROUND, ///
        SQUARE, ///
    }

    ///
    enum LINEJOIN
    {
        _DUMMY,
        MITER, ///
        ROUND, ///
        BEVEL, ///
    }

    float width;        ///
    LINECAP linecap;    /// not implemented;
    LINEJOIN linejoin;  /// not implemented;
    float miterlimit;   /// not implemented;
    float opacity;      ///
    bool dasharray;     /// not implemented;

    ///
    this(string i, float w, LINECAP lc, LINEJOIN lj, float m, float o)
    {
        id = i;
        width = w;
        linecap = lc;
        linejoin = lj;
        miterlimit = m;
        opacity = o;
    }

    void transform(in ref Matrix3f mat)
    { width *= mat[0]; }
}

/** 描画しない。
**/
class NoStroke : AStroke
{ this(){ super("", 0, LINECAP._DUMMY, LINEJOIN._DUMMY, 0, 0); } }

/** 単色で描画する。
**/
class Stroke : AStroke
{
    ///
    uint color;

    ///
    this()
    { super("", 1, LINECAP.BUTT, LINEJOIN.MITER, 1, 1); color = 0; }
    ///
    this(float w, LINECAP lc, LINEJOIN lj, float m, float o, uint c)
    { super("", w, lc, lj, m, o); color = c; }

    ///
    this(string i, float w, LINECAP lc, LINEJOIN lj, float m, float o, uint c)
    { super(i, w, lc, lj, m, o); color = c; }
}


/** フィルタに関するルートクラス。

このクラスからの実行時ダウンキャストで分類する。
**/
abstract class AFilter
{
    string id; ///
    ///
    this(string i){ id = i; }
    ///
    abstract void transform(in ref Matrix3f);
}

/// ガウスぼかし。
class GaussianBlurFilter : AFilter
{
    float stdDeviation; /// なにこれ？
    ///
    this(string i, float d) { super(i); stdDeviation = d; }

    override void transform(in ref Matrix3f mat){stdDeviation *= mat[0];}
}

/** Path もしくは、Path の集合である G のルートクラス。
**/
abstract class AG
{
    ///
    string id;
    ///
    this(string i = "") { id = i; }

    ///
    protected void calcSize(ref ViewBox){}

    ///
    abstract void transform(in ref Matrix3f);

    abstract override string toString() const;
}

/** Path の集合。Inkscape ではグループとレイヤに相当する。
**/
class G : AG
{
    AG[] g; ///

    ///
    this(string i){ super(i); }

    this(string i, AG[] ag)
    { super(i); g = ag; }

    //
    protected override void calcSize(ref ViewBox vb)
    { for (size_t i = 0; i < g.length; ++i) g[i].calcSize(vb); }

    override void transform(in ref Matrix3f m)
    { foreach (one; g) one.transform(m); }

    override string toString() const
    {
        import std.array : Appender, join;
        Appender!(string[]) buf;
        buf.reserve(g.length);
        foreach (one; g) buf.put(one.toString);
        return ["[", buf.data.join(", "), "]"].join;;
    }
}

/** Path を定義する。&lt;path&gt;の内容を格納する。

描画点を移動させるコマンドの列で表現されている。
**/
class Path : AG
{
    /// d 属性の中身を表現する。
    static class Command
    {
        ///
        enum TYPE
        {
            _ZERO, ///
            _DUMMY, ///
            MOVE, ///
            MOVE_R, /// relative one.
            LINE, ///
            LINE_R, ///
            HORZ, ///
            HORZ_R, ///
            VERT, ///
            VERT_R, ///
            CUBIC_BEZIER, ///
            CUBIC_BEZIER_R, ///
            SHORT_CUBIC_BEZIER, ///
            SHORT_CUBIC_BEZIER_R, ///
            QUADRATIC_BEZIER,     ///
            QUADRATIC_BEZIER_R,   ///
            SHORT_QUADRATIC_BEZIER, ///
            SHORT_QUADRATIC_BEZIER_R, ///
            ARC, ///
            ARC_R, ///
            Z, /// go to beginning.

            _Z_R, ///

            ELLIPSE, ///
            _ELLIPSE_R, ///
        }
        TYPE type; ///
        Vector2f pos; ///
        ///
        this(TYPE t, in float[2] p) { type = t; pos = p;}

        ///
        @property
        Command dup() const { return new Command(type, pos); }

        //
        protected void toAbs(in ref Command prev)
        {
            if (type & 1)
            {
                if (prev !is null)
                    pos += prev.pos;
                type = cast(TYPE)(type-1);
            }
        }

        ///
        void calcSize(ref ViewBox vb)
        {
            import std.math : isNaN;
            if      (__ctfe){}
            else if (vb.minX.isNaN || pos.x < vb.minX)
                vb.minX = pos.x;
            else if (vb.width.isNaN || vb.width < (pos.x - vb.minX))
                vb.width = pos.x - vb.minX;
            if      (__ctfe){}
            else if (vb.minY.isNaN || pos.y < vb.minY)
                vb.minY = pos.y;
            else if (vb.height.isNaN || vb.height < (pos.y - vb.minY))
                vb.height = pos.y - vb.minY;
        }

        ///
        void transform(in ref Matrix3f mat) { pos = mat * pos; }

        ///
        protected Command[] toLine(in float, in Command)
        { return [this]; }


        // genで表現される曲線を連続する直線へと変換する。
        protected static Command[] divide(in Command prev, Command[] input,
                                          in float lsq,
                                          Vector2f delegate(in float) gen)
        {
            assert(input.length < 1000, "too much dviding. over 1000.");

            if      (0 == input.length) return input;
            else if (prev.pos.distanceSq(input[0].pos) < lsq) return input;

            float t = 1.0f / (input.length * 2);
            auto newC = new Command[input.length*2];

            for (size_t i = 0; i < newC.length; ++i)
            {
                if (i%2 == 1)
                    newC[i] = input[i/2];
                else
                    newC[i] = new Command(TYPE.LINE, gen(t * (i + 1)));
            }
            return divide(prev, newC, lsq, gen);
        }

        override string toString() const
        {
            import std.string : join;
            import std.conv : to;
            return ["(", type.to!string, ", ", pos.to!string, ")"].join;
        }
    }

    /// Quadratic Bezier / Ellipse
    static final class Command2 : Command
    {
        ///
        Vector2f pos1;
        ///
        this(TYPE t, in float[2] p, in float[2] p1)
        { super(t, p); pos1 = p1; }

        //
        @property
        override Command2 dup() const { return new Command2(type, pos, pos1); }

        // 相対位置を絶対位置に。省略表現を展開。
        protected override void toAbs(in ref Command prev)
        {
            if (type & 1)
            {
                if (prev !is null)
                {
                    pos += prev.pos;
                    pos1 += prev.pos;
                }
                type = cast(TYPE)(type-1);
            }
            if (type == TYPE.SHORT_QUADRATIC_BEZIER)
            {
                if      (prev is null) pos1 = pos;
                else if (auto c3 = cast(Command3)prev)
                    pos1 = c3.pos + (c3.pos - c3.pos2);
                else if (auto c2 = cast(Command2)prev)
                    pos1 = c2.pos + (c2.pos - c2.pos1);
                else
                    pos1 = prev.pos;
                type = TYPE.QUADRATIC_BEZIER;
            }
        }

        /// 計算の中身は $(LINK #sworks.base.matrix.QuadraticBezier)を参照。
        override Command[] toLine(in float l, in Command prev)
        {
            if      (type == TYPE.QUADRATIC_BEZIER)
            {
                if (prev is null) return [this];
                auto qb = QuadraticBezier!float(prev.pos, pos1, pos);

                return divide(prev, [new Command(TYPE.LINE, pos)], l * l,
                              &qb.opCall);
            }
            else if (type == TYPE.ELLIPSE)
            {
                auto e = Ellipse!float(pos, pos1);
                auto p = new Command(TYPE.MOVE, e(0));
                return p ~ divide(p , [new Command(TYPE.LINE, e(0.25)),
                                        new Command(TYPE.LINE, e(0.5)),
                                        new Command(TYPE.LINE, e(0.75)),
                                        new Command(TYPE.LINE, e(1))],
                                  l * l, &e.opCall);
            }
            else assert(0);
        }

        override string toString() const
        {
            import std.string : join;
            import std.conv : to;
            return ["(", type.to!string, ", ", pos.to!string, ", ",
                    pos1.to!string, ")"].join;
        }
    }

    /// Cubic Bezier
    static final class Command3 : Command
    {
        ///
        Vector2f pos1, pos2;
        ///
        this(TYPE t, in float[2] p, in float[2] p1, in float[2] p2)
        { super(t, p); pos1 = p1; pos2 = p2; }

        //
        @property
        override Command3 dup() const
        { return new Command3(type, pos, pos1, pos2); }

        // 相対座標を絶対座標に。省略表現を展開。
        protected override void toAbs(in ref Command prev)
        {
            if (type & 1)
            {
                if (prev !is null)
                {
                    pos += prev.pos;
                    pos1 += prev.pos;
                    pos2 += prev.pos;
                }
                type = cast(TYPE)(type-1);
            }
            if (type == TYPE.SHORT_CUBIC_BEZIER)
            {
                if      (prev is null) pos1 = pos2;
                else if (auto c3 = cast(Command3)prev)
                    pos1 = c3.pos + (c3.pos - c3.pos2);
                else if (auto c2 = cast(Command2)prev)
                    pos1 = c2.pos + (c2.pos - c2.pos1);
                else
                    pos1 = prev.pos;
            }
        }

        //
        override Command[] toLine(in float l, in Command prev)
        {
            if (prev is null) return [this];
            auto cb = CubicBezier!float(prev.pos, pos1, pos2, pos);

            return divide(prev, [new Command(TYPE.LINE, pos)], l * l,
                          &cb.opCall);
        }

        override string toString() const
        {
            import std.string : join;
            import std.conv : to;
            return ["(", type.to!string, ", ", pos.to!string, ", ",
                    pos1.to!string, ", ", pos2.to!string, ")"].join;
        }
    }

    ///
    static final class CommandArc : Command
    {
        ///
        Vector2f radii;
        ///
        float x_axis_rotation;
        enum LARGE_ARC_FLAG = 1; ///
        enum SWEEP_FLAG = 1 << 1; ///
        private ubyte _flag; // bit 1 = large-arc-flag
                             // bit 2 = sweep-flag
        ///
        this(TYPE t, in float[2] p, in float[2] r,
             float xrot, int large, int sweep)
        {
            super(t, p);
            radii = r;
            x_axis_rotation = xrot;
            _flag = (0 < large ? LARGE_ARC_FLAG : 0)
                  | (0 < sweep ? SWEEP_FLAG : 0);
        }

        ///
        @property
        override CommandArc dup() const
        {
            return new CommandArc(type, pos, radii, x_axis_rotation,
                                  _flag & LARGE_ARC_FLAG,
                                  _flag & SWEEP_FLAG);
        }

        ///
        bool large_arc_flag() @property @nogc @safe const pure nothrow
        { return 0 < (_flag & LARGE_ARC_FLAG); }

        ///
        bool sweep_flag() @property @nogc @safe const pure nothrow
        { return 0 < (_flag & SWEEP_FLAG); }

        //
        override Command[] toLine(in float l, in Command prev)
        {
            if (prev is null) return [this];
            auto a = Arc!float(prev.pos, pos, radii, x_axis_rotation,
                               large_arc_flag, sweep_flag);
            return divide(prev, [new Command(TYPE.LINE, pos)], l * l,
                          &a.opCall);
        }

        override string toString() const
        {
            import std.string : join;
            import std.conv : to;
            return ["(", type.to!string, ")"].join;;
        }
    }

    //----------------------------------------------------------
    ///
    float opacity = 1.0f;
    ///
    AFill fill;
    ///
    AStroke stroke;
    ///
    AFilter filter;
    Path clip; /// クリッピング領域
    Matrix3f mat; ///
    string[] classes; ///

    Command[][] contour; ///

    ///
    this(){ super(); }
    ///
    this(Command[][] co){ super(); contour = co; }


    //
    protected override void calcSize(ref ViewBox vb)
    {
        for (size_t i = 0; i < contour.length; ++i)
        {
            for (size_t j = 0; j < contour[i].length; ++j)
                contour[i][j].calcSize(vb);
        }
    }

    //
    void normalize()
    {
        import std.array : Appender;
        enum LENGTH = 10;
        Command prev;
        for (size_t i = 0; i < contour.length; ++i)
        {
            // 相対位置を絶対位置に。省略表現を展開。
            for (size_t j = 0; j < contour[i].length; ++j)
            {
                contour[i][j].toAbs(prev);
                prev = contour[i][j];
            }

            // Z コマンドを LINE へと展開。
            if (0 < contour[i].length
              && contour[i][$-1].type == Command.TYPE.Z)
            {
                contour[i][$-1].pos = contour[i][0].pos;
                contour[i][$-1].type = Command.TYPE.LINE;
            }

            // 曲線コマンドを LINE へと展開。
            Appender!(Command[]) newC;
            for (size_t j = 0; j < contour[i].length; ++j)
            {
                auto c = contour[i][j].toLine(LENGTH, prev);
                if (0 < c.length)
                {
                    newC.put(c);
                    prev = c[$-1];
                }
            }
            contour[i] = newC.data;
        }

        //
        if (clip !is null) clip.normalize;
    }

    ///
    override void transform(in ref Matrix3f m)
    {
        auto m2 = m * mat;
        if (stroke !is null) stroke.transform(m2);
        if (fill !is null) fill.transform(m2);
        if (filter !is null) filter.transform(m2);
        if (clip !is null) clip.transform(m2);
        for (size_t i = 0; i < contour.length; ++i)
            for (size_t j = 0; j < contour[i].length; ++j)
                contour[i][j].transform(m2);
    }

    override string toString() const
    {
        import std.array : Appender, join;
        Appender!(string[]) buf;
        buf.put("Path(");
        foreach (c; contour)
        {
            buf.put("[");
            foreach (c2; c) buf.put(c2.toString);
            buf.put("]");
        }
        buf.put(")");
        return buf.data.join;
    }
}

//------------------------------------------------------------------------------
/// 巡回
/// svg 内の Path を巡回する。
void eachPath()(auto ref SVG svg, void delegate(Path) proc)
{ foreach (g; svg.g) g.eachPath(proc); }
//
private void eachPath(AG g, void delegate(Path) proc)
{
    if      (auto pp = cast(Path)g) proc(pp);
    else if (auto pg = cast(G)g)
        foreach (one; pg.g) one.eachPath(proc);
}

/// xml を巡回して style要素を適用する。
@trusted
AXML applyCSS(AXML xml, CSS outer = null)
{
    if (outer is null) outer = new CSS(Ns("style"));
    foreach (one; xml)
        if (auto css = cast(CSSAttr)one)
            outer.children ~= css;

    if (auto x = cast(XML)xml)
        outer.appendStyleTo(x);
    return xml;
}

/** xml の属性値として CSS の内容を適用する。
 *
 * 子要素にも適用される。
 */
@trusted
void appendStyleTo(CSS css, XML xml, XML[] parents = null)
{
    foreach (one; css.children)
        if (auto attr = cast(CSSAttr)one)
            if (attr.rule.match(xml, parents))
                xml.attr.gatherStyle(attr.attr);

    parents ~= xml;
    foreach (child; xml.children)
        if (auto one = cast(XML)child)
            css.appendStyleTo(one, parents);
}

//------------------------------------------------------------------------------
//
// PolyPath
//
//------------------------------------------------------------------------------
/** 正規化済みの SVG ファイルを格納する。
正規化後の SVG は Polyline のみで構成されているとする。
**/
struct SVGPL
{
    ///
    PolyLines[] lines;
    /// width, hight にはstrokeの幅は考慮されていないので注意。
    float width, height;
}

/** SVGのPathを MOVE と LINE に展開したものを表現する。
**/
struct PolyLines
{
    string id; ///
    string[] classes; ///
    Vector2f[][] clip; ///

    float opacity; ///
    AFill fill; ///
    AStroke stroke; ///
    AFilter filter; ///

    Vector2f[][] pos; ///

    bool haveClass(string c)
    {
        foreach (one; classes)
            if (one == c) return true;
        return false;
    }
}

///
SVGPL toPolyLines()(auto ref SVG svg)
{
    SVGPL result;
    result.width = svg.viewBox.width;
    result.height = svg.viewBox.height;
    svg.eachPath((p){ result.lines ~= p.toPolyLines; });
    return result;
}

//
private PolyLines toPolyLines(Path p)
{
    import std.math : isNaN;
    PolyLines result;
    result.id = p.id;
    result.opacity = p.opacity;
    result.fill = p.fill;
    result.stroke = p.stroke;
    result.filter = p.filter;
    result.classes = p.classes;

    if (result.fill is null && result.stroke is null)
        result.stroke = new Stroke;

    // LinearGradient の x1, y1, x2, y2 が設定されていない場合は、
    // 横向きで端から端まで。
    if (auto lg = cast(LinearGradient)result.fill)
    {
        if (lg.pos1.x.isNaN)
        {
            ViewBox vb;
            p.calcSize(vb);
            lg.pos1 = Vector2f(vb.minX, vb.minY);
            lg.pos2 = Vector2f(vb.minX + vb.width, vb.minY);
        }
    }

    if (p.clip !is null) result.clip = p.clip.contour.toPolyLines;
    result.pos = p.contour.toPolyLines;
    return result;
}

private Vector2f[][] toPolyLines(Path.Command[][] contour)
{
    auto pos = new Vector2f[][contour.length];
    for (size_t i = 0; i < contour.length; ++i)
    {
        pos[i] = new Vector2f[contour[i].length];
        for (size_t j = 0; j < contour[i].length; ++j)
            pos[i][j] = contour[i][j].pos;
    }
    return pos;
}

//------------------------------------------------------------------------------
//
// normalizing
//
//------------------------------------------------------------------------------
/** 後々使い易いように。

<ol>
  <li>相対位置を絶対位置に。</li>
  <li>省略表現(ベジエ曲線の制御点の省略とか)を展開。</li>
  <li>パスを閉じるコマンドを line to へ展開</li>

  <li>曲線の表現を直線へと分割する。</li>
  <li>座標を正規化し、x = [0, W], y = [0, H] に分布するように。</li>
</ol>

**/
auto normalize()(auto ref SVG svg, in float W, in float H)
{
    svg.eachPath(p=>p.normalize);
    if (svg.viewBox.empty)
        svg.eachPath(p=>p.calcSize(svg.viewBox));

    auto mat = Matrix3f.scaleMatrix(W/svg.viewBox.width, H/svg.viewBox.height)
             * Matrix3f.translateMatrix(-svg.viewBox.minX, -svg.viewBox.minY);

    foreach (one; svg.g) one.transform(mat);

    if (!svg.viewBox.empty)
        svg.viewBox = ViewBox(0, 0, W, H);

    return svg;
}

//==============================================================================
//------------------------------------------------------------------------------
//
// Parser
//
//------------------------------------------------------------------------------
//==============================================================================

/// suger
SVG toSVG(string buf, int width, int height = 0)
{ return buf.toCache.toSVG(width, height); }

/// TICache から SVG に。
SVG toSVG(TICache!char buf, int width, int height = 0)
{
    auto info = new SVGParserInfo(SVG_URI);
    foreach (axml; buf.toXML!(XML_PARSER_PROPERTY.STANDARD)(info).applyCSS)
    {
        if (auto xml = cast(XML)axml)
            if (xml.name == "svg") return xml.toSVG(width, height);
    }
    throw new Exception("NO SVG DETECTED.");
}

/// <svg> から SVGに。
SVG toSVG(XML xml, int width, int height = 0)
{
    import std.math : isNaN;
    assert(xml.name == "svg");

    SVG svg;
    float svgWidth, svgHeight;
    UnitHV ul;
    ul.h.size = width;

    svgWidth = xml.attr.getInch("width", ul.h);
    svgHeight = xml.attr.getInch("height", ul.v);

    if (height <= 0 && 0 < svgWidth && 0 < svgHeight)
        height = cast(int)(width * svgHeight / svgWidth);
    ul.v.size = height;

    if      (auto vbv = xml.attr.getAs!ViewBoxValue("viewBox"))
        svg.viewBox = vbv.value;
    else if (0 < svgWidth && 0 < svgHeight)
        svg.viewBox = ViewBox(0, 0, width, width * svgHeight / svgWidth);
    else
        svg.viewBox = ViewBox(0, 0, width, height);

    if      (0 < svgWidth)
        ul.h.ppi = svg.viewBox.width / svgWidth;
    if      (0 < svgHeight)
        ul.v.ppi = svg.viewBox.height / svgHeight;

    foreach (axml; xml.children)
        if (auto one = cast(XML)axml)
            if (auto g = one.toG(xml.attr, ul)) svg.g ~= g;

    return svg.normalize(width, height);
}

// SVG の表示に関係ある部分の属性値を集める。
// attrIn は劣後
private void gatherStyle(ref Attribute attrOut, in Attribute attrIn)
{
    void merge(string key)
    {
        if (key !in attrOut)
            if (auto pv = key in attrIn)
                attrOut[key] = (*pv);
    }
    void mergeOpacity(string key)
    {
        attrOut[key] = new FloatValue(attrOut.get!FloatValue(key, 1)
                                     * attrIn.get!FloatValue(key, 1));
    }

    mergeOpacity("opacity");
    merge("fill");
    mergeOpacity("fill-opacity");
    merge("fill-rule");
    merge("stroke");
    merge("stroke-width");
    merge("stroke-linecap");
    merge("stroke-linejoin");
    merge("stroke-miterlimit");
    merge("stroke-dasharray");
    mergeOpacity("stroke-opacity");
    merge("clip-path");
    merge("filter");

    attrOut["transform"] = new Matrix3fValue(
        attrIn.get!Matrix3fValue("transform")
         * attrOut.get!Matrix3fValue("transform"));

    merge("x");
    merge("y");
    merge("width");
    merge("height");
}

private AG toG(XML xml, in Attribute attr, in ref UnitHV ul)
{
    xml.attr.gatherStyle(attr);
    switch(xml.name.value)
    {
        case        "g": case "use":
            auto g = new G(xml.attr["id"]);
            foreach (child; xml.children)
                if (auto one = cast(XML)child)
                    if (auto g2 = one.toG(xml.attr, ul)) g.g ~= g2;
            return g;
        break; case "path": return xml.toPath(ul);
        break; case "ellipse": return xml.ellipseToPath(ul);
        break; case "rect": return xml.rectToPath(ul);
        break; case "symbol": return xml.symbolToPath(ul);
        break; default:
    }
    return null;
}

// <path> から Path へ
private Path toPath(XML xml, in UnitHV ul)
{
    import std.array : array;
    import std.algorithm : filter;
    import std.string : split;
    assert(xml.name == "path");
    alias C = Path.Command;
    auto p = new Path;
    xml.attr.fillStyle(p, ul);
    p.classes = xml.attr["class"].split(" ").filter!"0 < a.length".array;
    if (auto cv = xml.attr.get!CommandValue("d"))
    {
        p.contour = new C[][cv.length];
        for (size_t i = 0; i < cv.length; ++i)
        {
            p.contour[i] = new C[cv[i].length];
            for (size_t j = 0; j < cv[i].length; ++j)
                p.contour[i][j] = cv[i][j].dup;
        }
    }
    return p;
}

/* XML の属性及び、style属性から $(LINK, #sworks.svg.Style)を得る。
 */
private void fillStyle(in Attribute attr, Path s, in ref UnitHV ul)
{
    import std.math : isNaN;
    s.id = attr["id"];
    s.clip = attr.get!XMLValue("clip-path").toClipPath(ul);
    s.opacity = attr.get!FloatValue("opacity", 1);
    s.fill = attr.toFill(ul);
    s.stroke = attr.toStroke(ul);
    s.mat = attr.get!Matrix3fValue("transform");
    s.filter = attr.get!XMLValue("filter").toFilter;
}


// fill とか、stroke とかの none を getStyleAs で受ける為だけのもの。
private enum NONETYPE
{
    _DUMMY,
    NONE,
}

// XML の属性及び、style属性から fill を得る。
private AFill toFill(in Attribute attr, in ref UnitHV ul)
{
    import std.string : toUpper;
    alias R = AFill.RULE;
    float opacity = 1.0;
    R rule;

    void fillOther()
    {
        opacity = attr.get!FloatValue("fill-opacity", 1);
        rule = attr.getAs!R("fill-rule");
    }

    if      (auto cv = attr.getAs!ColorValue("fill"))
    {
        fillOther;
        return new Fill(opacity, rule, cv.value);
    }
    else if (auto x = cast(const(XML))attr.get!XMLValue("fill"))
    {
        switch(x.name.value)
        {
            case        "linearGradient":
                fillOther;
                auto lg = x.toLinearGradient(attr, ul);
                lg.opacity *= opacity;
                lg.rule = rule;
                return lg;
            break; case "radialGradient":
                fillOther;
                auto lg = x.toRadialGradient(attr, ul);
                lg.opacity *= opacity;
                lg.rule = rule;
                return lg;
            break; default:
        }
    }
    else if (NONETYPE.NONE == attr.getAs!NONETYPE("fill"))
        return new NoFill;
    return null;
}

// <path>要素の style属性から AStrokeのインスタンスを得る。
private AStroke toStroke(in Attribute attr, in ref UnitHV ul)
{
    alias C = AStroke.LINECAP;
    alias J = AStroke.LINEJOIN;
    C c;
    J j;
    float width = 1.0;
    float miterlimit;
    float opacity = 1.0;
    void fillOther()
    {
        c = attr.getAs!C("stroke-linecap");
        j = attr.getAs!J("stroke-linejoin");
        opacity = attr.get!FloatValue("stroke-opacity", 1);
        width = attr.get!FloatValue("stroke-width", 1);
    }
    if (auto v = "stroke" in attr)
    {
        if      (auto cv = cast(ColorValue)(*v))
        {
            fillOther;
            return new Stroke(width, c, j, miterlimit, opacity, cv.value);
        }
        else if (NONETYPE.NONE == (*v).getAs!NONETYPE)
            return new NoStroke;
    }
    return null;
}


// <radialGradient> から RadialGradient へ
private RadialGradient toRadialGradient(in XML xml,
                                        in Attribute attr,
                                        in ref UnitHV ul)
{
    auto rg = new RadialGradient;
    xml.fillLinearGradient(rg, attr, ul);
    rg.pos1.x = xml.attr.getPixel("cx", ul.h);
    rg.pos1.y = xml.attr.getPixel("cy", ul.v);
    rg.pos2.x = xml.attr.getPixel("fx", ul.h);
    rg.pos2.y = xml.attr.getPixel("fy", ul.v);
    rg.radius = xml.attr.getPixel("r", ul.h);
    rg.matrix = xml.attr.get!Matrix3fValue("gradientTransform");
    return rg;
}

// <linearGradient> から LinearGradient へ
private LinearGradient toLinearGradient(in XML xml,
                                        in Attribute attr,
                                        in ref UnitHV ul)
{
    auto lg = new LinearGradient;
    xml.fillLinearGradient(lg, attr, ul);
    return lg;
}
//
private void fillLinearGradient(in XML xml, LinearGradient lg,
                                in Attribute attr,
                                in ref UnitHV ul)
{
    import std.array : Appender;

    lg.id = xml.attr["id"];
    lg.opacity = xml.attr.get!FloatValue("opacity", 1);
    lg.pos1.x = xml.attr.getPixel("x1", ul.h, attr.getPixel("x", ul.h));
    lg.pos1.y = xml.attr.getPixel("y1", ul.v, attr.getPixel("y", ul.v));
    lg.pos2.x = xml.attr.getPixel("x2", ul.h,
         attr.getPixel("x", ul.h) + attr.getPixel("width", ul.h));
    lg.pos2.y = xml.attr.getPixel("y2", ul.v,
         attr.getPixel("y", ul.v) + attr.getPixel("height", ul.v));

    Appender!(LinearGradient.Stop[]) ss;
    ss.reserve(xml.children.length);
    foreach (child; xml.children)
        if (auto one = cast(XML)child)
            if ("stop" == one.name)
                    ss.put(one.toLinearStop);
    lg.stops = ss.data;
}

// <stop> から LinearGradient.Stop へ
private auto toLinearStop(in XML xml)
{
    assert(xml.name == "stop");
    LinearGradient.Stop s;
    s.id = xml.attr["id"];
    s.offset = xml.attr.get!FloatValue("offset", 0);
    s.color = xml.attr.get!UintValue("stop-color");
    s.opacity = xml.attr.get!FloatValue("stop-opacity", 1);

    return s;
}


// <filter> から AFilter へ
private AFilter toFilter(in AXML axml)
{
    auto xml = cast(XML)axml;
    if (xml is null) return null;
    foreach (one; xml)
    {
        if (auto child = cast(XML)one)
        {
            switch(child.name.value)
            {
                case        "feGaussianBlur":
                    return new GaussianBlurFilter(xml.attr["id"],
                         child.attr.get!FloatValue("stdDeviation", 0));
                break; default:
            }
        }
    }
    return null;
}

//
private AG symbolToPath(XML xml, in UnitHV ul)
{
    import std.array : Appender;
    auto vb = xml.attr.get!ViewBoxValue("viewBox");
    auto x = xml.attr.getPixel("x", ul.h);
    auto y = xml.attr.getPixel("y", ul.v);
    auto w = xml.attr.getPixel("width", ul.h);
    auto h = xml.attr.getPixel("height", ul.v);
    xml.attr["transform"] = new Matrix3fValue(
          xml.attr.get!Matrix3fValue("transform")
        * Matrix3f.translateMatrix(x, y)
        * Matrix3f.scaleMatrix(w/vb.width, h/vb.height)
        * Matrix3f.translateMatrix(-vb.minX, -vb.minY));


    Appender!(AG[]) children;
    children.reserve(xml.children.length);
    foreach (child; xml.children)
        if (auto one = cast(XML)child)
            if (auto g = one.toG(xml.attr, ul)) children.put(g);

    return new G(xml.attr["id"], children.data);
}

//
private Path toClipPath(in AXML axml, in ref UnitHV ul)
{
    auto xml = cast(XML)axml;
    if (xml is null) return null;
    assert(xml.name == "clipPath");
    foreach (child; xml.children)
        if (auto one = cast(XML)child)
            if (one.name == "path") return one.toPath(ul);
    return null;
}


//
private Path ellipseToPath(XML xml, in ref UnitHV ul)
{
    assert(xml.name == "ellipse");
    alias C = Path.Command;
    alias C2 = Path.Command2;
    auto p = new Path;
    xml.attr.fillStyle(p, ul);
    auto cx = xml.attr.getPixel("cx", ul.h);
    auto cy = xml.attr.getPixel("cy", ul.v);
    auto rx = xml.attr.getPixel("rx", ul.h);
    auto ry = xml.attr.getPixel("ry", ul.v);
    p.contour = [[new C2(C.TYPE.ELLIPSE, [cx, cy], [rx, ry])]];
    return p;
}

//
private Path rectToPath(in XML xml, in UnitHV ul)
{
    assert(xml.name == "rect");
    alias C = Path.Command;
    auto p = new Path;
    xml.attr.fillStyle(p, ul);

    auto x = xml.attr.getPixel("x", ul.h);
    auto y = xml.attr.getPixel("y", ul.v);
    auto width = xml.attr.getPixel("width", ul.h);
    auto height = xml.attr.getPixel("height", ul.v);
    p.contour = [[new C(C.TYPE.MOVE, [x, y]),
                  new C(C.TYPE.LINE, [x+width, y]),
                  new C(C.TYPE.LINE, [x+width, y+height]),
                  new C(C.TYPE.LINE, [x, y+height]),
                  new C(C.TYPE.LINE, [x, y])]];
    return p;
}

//==============================================================================
// sworks.xml パーサ関連

///
class SVGParserInfo : /*sworks.xml.*/XMLParserInfo
{
    //
    private XML[string]* defs;
    ///
    @trusted @nogc pure nothrow
    this() const {}
    ///
    @trusted pure nothrow
    this(string defns)
    {super(defns); defs = (new XML[string][1]).ptr;}
    ///
    @trusted pure nothrow
    this(string[string] v)
    { super(v); defs = (new XML[string][1]).ptr; }
    ///
    @trusted @nogc pure nothrow
    private this(XML[string]* d) { super(); defs = d; }

    //
    override protected @trusted pure
    XMLParserInfo diveCopyTo(XMLParserInfo i, XML c)
    {
        super.diveCopyTo(i, c);
        if (auto s = cast(SVGParserInfo)i) s.defs = defs;
        return i;
    }
    //
    override @trusted pure
    XMLParserInfo dive(Ns n)
    {
        if (n == "style")
            return super.diveCopyTo(new SVGParserInfo(defs), new CSS(n));
        else
            return super.diveCopyTo(new SVGParserInfo(defs), new XML(n));
    }

    //
    @trusted @nogc pure
    private const(XML) findXML(string key)
    {
        if (auto pxml = key in (*defs)) return (*pxml);
        return null;
    }

    //
    @trusted pure
    private void addXML(string key){ (*defs)[key] = current; }

    @trusted override
    AttributeValue attrValueParser(TICache!char buf, in Ns key)
    {
        import std.string : stripRight;
        switch(key.value)
        {
            case        "style":
                parseStyle(buf);
                return null;
            break; case "width": case "height": case "cx": case "cy":
                   case "rx": case "ry": case "x": case "y":
                   case "stroke-width": case "offset": case "x1": case "x2":
                   case "y1": case "y2": case "fx": case "fy": case "r":
                return buf.munchLength;
            break; case "stdDeviation":
                return new FloatValue(buf.munchFloating);
            break; case "href":
                if (auto x = findXML(buf.getIDTarget))
                {
                    if ("use" == current.name)
                        current.children ~= x.dup;
                    else
                    {
                        current.attr.gatherStyle(x.attr);
                        current.children ~= x.dupChildren;
                    }
                }
            break; case "clip-path":
                if (auto x = findXML(buf.getURLTarget))
                    return new XMLValue(x);
            break; case "d":
                return buf.parseD;
            break; case "gradientTransform": case "transform":
                return buf.parseMatrix3f;
            break; case "viewBox":
                return buf.parseViewBox;
            break; case "stroke": case "fill":
                if      (auto c = buf.munchColor) return c;
                else if (auto x = findXML(buf.getURLTarget))
                    return new XMLValue(x);
            break; case "stop-color":
                if (auto c = buf.munchColor) return c;
            break; case "id":
                auto sv = buf.munchStringValue;
                addXML(sv.toString);
                return sv;
            break; case "class":
                return buf.munchClassValue;
            break; default:
                return buf.munchStringValue;
        }
        return null;
    }

    @trusted override
    AXML contentsParser(TICache!char buf)
    {
        if (auto css = cast(CSS)current)
            css.children = buf.toCSS(this);
        return null;
    }

    // style 属性をパースする。
    @trusted protected override
    AttributeValue styleValueParser(TICache!char buf, in Ns key)
    {
        import std.string : stripRight;
        import std.algorithm : endsWith;
        alias R = AFill.RULE;
        switch(key.value.endsWith("color", "fill", "stroke", "opacity", "width",
                                  "miterlimit", "filter"))
        {
            case        1: .. case 3:
                if      (auto c = buf.munchColor) return c;
                else if (auto x = findXML(buf.getURLTarget))
                    return new XMLValue(x);
            break; case 4: .. case 6:
                return new FloatValue(buf.munchFloating);
            break; case 7:
                if (auto x = findXML(buf.getURLTarget))
                    return new XMLValue(x);
            break; default:
                return buf.munchStringValue;
        }
        return null;
    }
}

// suger
private
float getInch(in ref Attribute attr, string key, in ref UnitLength ul,
              lazy float def = float.nan)
{
    if (auto v = attr.getAs!LengthValue(key)) return v.toInch(ul);
    return def;
}

// ditto
private
int getPixel(in ref Attribute attr, string key, in ref UnitLength ul,
             lazy int def = 0)
{
    if (auto v = attr.getAs!LengthValue(key)) return v.toPixel(ul);
    return def;
}

//
private
T getAs(T)(in AttributeValue av) if (is(T == enum))
{
    import std.conv : to;
    import std.string : toUpper;
    return av.toString.toUpper.to!T;
}

// parseViewBoxの戻り値
private class ViewBoxValue : AttributeValue
{
    ViewBox value;
    this(in ViewBox v){ value = v; }
}

// viewBox属性をパースする。
private AttributeValue parseViewBox(TICache!char buf)
{
    ViewBox vb;
    buf.munchFloatingToFill(vb);
    return new ViewBoxValue(vb);
}

// parseD の戻り値
private class CommandValue : AttributeValue
{
    Path.Command[][] value;
    this(Path.Command[][] v){ value = v; }
}

// <path>要素の d属性をパースする。
private AttributeValue parseD(TICache!char buf)
{
    import std.conv : to;
    alias T = Path.Command.TYPE;
    auto type = T._DUMMY;
    Path.Command[][] cs;
    Path.Command[] c;

    Vector2f pos, pos1, pos2;
    float f;
    int[2] flag;

    for (;;)
    {
        buf.stripLeftWhite;
        if (buf.empty) break;
        switch(buf.front)
        {
            case 'M': type = T.MOVE;                     goto case ' ';
            case 'm': type = T.MOVE_R;                   goto case ' ';
            case 'L': type = T.LINE;                     goto case ' ';
            case 'l': type = T.LINE_R;                   goto case ' ';
            case 'H': type = T.HORZ;                     goto case ' ';
            case 'h': type = T.HORZ_R;                   goto case ' ';
            case 'V': type = T.VERT;                     goto case ' ';
            case 'v': type = T.VERT_R;                   goto case ' ';
            case 'C': type = T.CUBIC_BEZIER;             goto case ' ';
            case 'c': type = T.CUBIC_BEZIER_R;           goto case ' ';
            case 'S': type = T.SHORT_CUBIC_BEZIER;       goto case ' ';
            case 's': type = T.SHORT_CUBIC_BEZIER_R;     goto case ' ';
            case 'Q': type = T.QUADRATIC_BEZIER;         goto case ' ';
            case 'q': type = T.QUADRATIC_BEZIER_R;       goto case ' ';
            case 'T': type = T.SHORT_QUADRATIC_BEZIER;   goto case ' ';
            case 't': type = T.SHORT_QUADRATIC_BEZIER_R; goto case ' ';
            case 'A': type = T.ARC;                      goto case ' ';
            case 'a': type = T.ARC_R;                    goto case ' ';
            case 'Z': case 'z': type = T.Z;              goto case ' ';
            case ' ': buf.popFront;
            default:
        }

        if (0 < c.length && (type == T.MOVE || type == T.MOVE_R))
        { cs ~= c; c.length = 0; }
        switch(type)
        {
            case        T.MOVE: .. case T.LINE_R:
                buf.munchFloatingToFill(pos.v);
                c ~= new Path.Command(type, pos);
            break; case T.HORZ: case T.HORZ_R:
                pos.x = buf.munchFloating;
                pos.y = 0;
                c ~= new Path.Command(type, pos);
            break; case T.VERT: case T.VERT_R:
                pos.x = 0;
                pos.y = buf.munchFloating;
                c ~= new Path.Command(type, pos);
            break; case T.CUBIC_BEZIER: case T.CUBIC_BEZIER_R:
                buf.munchFloatingToFill(pos1.v);
                buf.munchFloatingToFill(pos2.v);
                buf.munchFloatingToFill(pos.v);
                c ~= new Path.Command3(type, pos, pos1, pos2);
            break; case T.SHORT_CUBIC_BEZIER: case T.SHORT_CUBIC_BEZIER_R:
                pos1[] = 0;
                buf.munchFloatingToFill(pos2.v);
                buf.munchFloatingToFill(pos.v);
                c ~= new Path.Command3(type, pos, pos1, pos2);
            break; case T.QUADRATIC_BEZIER: case T.QUADRATIC_BEZIER_R:
                buf.munchFloatingToFill(pos1.v);
                buf.munchFloatingToFill(pos.v);
                c ~= new Path.Command2(type, pos, pos1);
            break; case T.SHORT_QUADRATIC_BEZIER:
                   case T.SHORT_QUADRATIC_BEZIER_R:
                pos1[] = 0;
                buf.munchFloatingToFill(pos.v);
                c ~= new Path.Command2(type, pos, pos1);
            break; case T.ARC: case T.ARC_R:
                buf.munchFloatingToFill(pos.v);
                f = buf.munchFloating;
                buf.fillLONGS(flag);
                buf.munchFloatingToFill(pos1.v);
                c ~= new Path.CommandArc(type, pos1, pos, f, flag[0], flag[1]);
            break; case T.Z:
                pos[] = 0;
                c ~= new Path.Command(type, pos);
            break; default:
        }

        if      (type == T.MOVE) type = T.LINE;
        else if (type == T.MOVE_R) type = T.LINE_R;
    }
    if (0 < c.length) cs ~= c;

    return new CommandValue(cs);
}


// url(#anIdOfTheObject) みたいなんから "anIdOfTheObject" を得る。
private string getURLTarget(TICache!char buf)
{
    if ("url(#" != buf.peek(5)) return null;
    else buf.popFront(5);
    for (auto c = buf.front; !buf.empty && c != ')' ; c = buf.push){}
    return buf.istack;
}

// #anIdOfTheObject みたいなんから "anIdOfTheObject" を得る。
private string getIDTarget(TICache!char buf)
{
    if ('#' != buf.front) return null;
    for (buf.popFront; !buf.empty; buf.push){}
    auto i = buf.istack;
    buf.flush;
    return i;
}

//
private class Matrix3fValue : AttributeValue
{
    Matrix3f value;
    this()(in auto ref Matrix3f m){ value = m; }
}

//
private Matrix3fValue parseMatrix3f(TICache!char buf)
{
    Matrix3f mat;

    bool check(TICache!char b, in string key)
    {
        b.stripLeftWhite;
        if (key == buf.peek(key.length))
        {
            buf.popFront(key.length);
            b.stripLeftWhite;
            if (b.front == '(') { b.popFront; return true; }
            else assert(0);
        }
        return false;
    }

    for (; !buf.empty;)
    {
        if      (check(buf, "matrix"))
        {
            Matrix3f m;
            buf.munchFloatingToFill(m[0..2]);
            buf.munchFloatingToFill(m[3..5]);
            buf.munchFloatingToFill(m[6..8]);
            mat *= m;
        }
        else if (check(buf, "translate"))
            mat *= Matrix3f.translateMatrix(buf.munchFloating,
                                            buf.munchFloating);
        else if (check(buf, "rotate"))
            mat *= Matrix3f.rotateMatrix(buf.munchFloating * TO_RADIAN);
        else if (check(buf, "scale"))
            mat *= Matrix3f.scaleMatrix(buf.munchFloating,
                                        buf.munchFloating);

        buf.findSkip(')');
    }

    return new Matrix3fValue(mat);
}

