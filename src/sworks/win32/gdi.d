/** オーナードローGDI用。
Dmd:        2.071.0
Date:       2016-May-01 16:41:46
Authors:    KUMA
License:    CC0
*/
module sworks.win32.gdi;
pragma(lib,"gdi32.lib");
pragma(lib, "Msimg32.lib"); // AlphaBlend とか、GradientFill とか。

import sworks.win32.util;
import sworks.base.matrix;

debug import sworks.win32.dump;


//------------------------------------------------------------------------------
/// Wnd のシュガー
auto dc(T)(Wnd wnd, scope T delegate(Dc) proc)
{
    static if (is(T == void))
    {
        auto hdc = GetDC(wnd.ptr);
        proc(Dc(hdc));
        ReleaseDC(wnd.ptr, hdc);
    }
    else
    {
        auto hdc = GetDC(wnd.ptr);
        auto t = proc(Dc(hdc));
        ReleaseDC(wnd.ptr, hdc);
        return t;
    }
}

import std.traits : isCallable;
//------------------------------------------------------------------------------
/// void wm_paint(Dc, ref PAINTSTRUCT) を得る。
template IsPaintHandler(f...) if (1 == f.length && isCallable!f)
{
    import std.traits : ParameterTypeTuple, ParameterStorageClassTuple,
                       ParameterStorageClass, Unqual;
    alias TYPE = ParameterTypeTuple!f;
    alias PSCT = ParameterStorageClassTuple!f;
    enum IsPaintHandler = 2 == TYPE.length
                       && is(TYPE[0] : Dc)
                       && is(TYPE[1] : PAINTSTRUCT)
                       && PSCT[1] == ParameterStorageClass.ref_;
}

//------------------------------------------------------------------------------
/// HDC のラッパ
struct Dc
{
    HDC _payload; ///
    /// 中身
    @property @nogc pure nothrow
    auto ptr() inout { return _payload; }

    ///
    @property @nogc
    void getBITMAP(ref BITMAP bm)
    { GetObject(GetCurrentObject(_payload, OBJ_BITMAP), BITMAP.sizeof, &bm); }

    ///
    void clear()
    { if (_payload) DeleteDC(_payload); _payload = null; }
    ///
    @property @trusted @nogc pure nothrow
    bool empty() const { return _payload is null; }

    ///
    @trusted @nogc pure nothrow
    bool opEquals(in Dc d) const
    { return d._payload is _payload; }

    ///
    @trusted @nogc pure nothrow
    bool opEquals(in BitmapDc d) const
    { return d.dc._payload is _payload; }

    @trusted @nogc pure nothrow
    private static RECT toRECT(int x, int y, int w, int h)
    {
        return RECT(0 < w ? x : x + w, 0 < h ? y : y + h,
                    0 < w ? x + w : x, 0 < h ? y + h : y);
    }

    void move(int x, int y)
    { MoveToEx(_payload, x, y, null); }

    void line(int x, int y)
    { LineTo(_payload, x, y); }

    /// 現在のブラシを使う。
    void fill()(in auto ref RECT rc)
    {
        Rectangle(_payload, rc.left, rc.top, rc.right, rc.bottom);
        MoveToEx(_payload, rc.right, rc.bottom, null);
    }
    /// ditto
    void fill(int x, int y, int w, int h)
    { auto rc = toRECT(x, y, w, h); fill(rc); }
    /// ditto
    void fill(int w, int h)
    {
        POINT p; MoveToEx(_payload, 0, 0, &p);
        auto rc = toRECT(p.x, p.y, w, h);
        fill(rc);
    }

    /// ブラシをハンドルで指定
    void fill()(in auto ref RECT rc, HBRUSH br)
    {
        FillRect(_payload, &rc, br);
        MoveToEx(_payload, rc.right, rc.bottom, null);
    }
    /// ditto
    void fill(int x, int y, int w, int h, HBRUSH br)
    { auto rc = toRECT(x, y, w, h); fill(rc, br); }
    /// ditto
    void fill(int w, int h, HBRUSH br)
    {
        POINT p; MoveToEx(_payload, 0, 0, &p);
        auto rc = toRECT(p.x, p.y, w, h);
        fill(rc, br);
    }
    /// ditto
    void fill(int x, int y, int w, int h, ubyte r, ubyte g, ubyte b)
    {
        auto br = CreateSolidBrush(RGB(r, g, b));
        auto rc = toRECT(x, y, w, h);
        FillRect(_payload, &rc, br);
        DeleteObject(br);
    }
    /// ditto
    void fill(int x, int y, int w, int h, COLORREF c)
    {
        auto br = CreateSolidBrush(c);
        auto rc = toRECT(x, y, w, h);
        FillRect(_payload, &rc, br);
        DeleteObject(br);
    }

    /** BR の名前のブラシを得る。
    GetStockObject か、 GetSysColorBrush を呼び出す。
    もしくは、 "255 150 100" みたいな文字列を色としてブラシを作る。
    */
    static HBRUSH getBrush(string BR)()
    {
        import std.string : toUpper;

        static if      (is(typeof(mixin(BR.toUpper ~ "_BRUSH"))))
            return GetStockObject(mixin(BR.toUpper ~ "_BRUSH"));
        else static if (is(typeof(mixin("COLOR_" ~ BR.toUpper))))
            return GetSysColorBrush(mixin("COLOR_" ~ BR.toUpper));
        else static if (is(typeof(mixin("COLOR" ~ BR.toUpper))))
            return GetSysColorBrush(mixin("COLOR" ~ BR.toUpper));
        else
        {
            import sworks.util.panel : toRGB;
            enum C = BR.toRGB;
            return CreateSolidBrush(C);
        }
    }
    //
    @trusted @nogc pure nothrow
    static bool definedBrush(string BR)()
    {
        import std.string : toUpper;
        static if      (is(typeof(mixin(BR.toUpper ~ "_BRUSH"))))
            return true;
        else static if (is(typeof(mixin("COLOR_" ~ BR.toUpper))))
            return true;
        else static if (is(typeof(mixin("COLOR" ~ BR.toUpper))))
            return true;
        else
            return false;
    }

    /// BR の名前のブラシを選択する。
    HBRUSH selectBrush(string BR)()
    { return SelectObject(_payload, getBrush!BR); }

    /// ブラシを名前で指定
    void fill(string BR)(in auto ref RECT rc)
    {
        static if (BR == "WHITE" || BR == "BLACK")
            fill!BR(rc.left, rc.top, rc.right - rc.left, rc.bottom - rc.top);
        else
        {
            auto b = getBrush!BR;
            FillRect(_payload, &rc, b);
            MoveToEx(_payload, rc.right, rc.bottom, null);
            static if (!Dc.definedBrush!BR)
                DeleteObject(b);
        }
    }
    /// ditto
    void fill(string BR)(int x, int y, int w, int h)
    {
        static if (BR == "WHITE" || BR == "BLACK")
        {
            BitBlt(_payload, x, y, w, h, null, 0, 0, mixin(BR ~ "NESS"));
            MoveToEx(_payload, x + w, y + h, null);
        }
        else
        {
            auto rc = RECT(x, y, x + w, y + h);
            fill!BR(rc);
        }
    }
    /// ditto
    void fill(string BR)(int w, int h)
    {
        POINT p; MoveToEx(_payload, 0, 0, &p);
        static if (BR == "WHITE" || BR == "BLACK")
            fill!BR(p.x, p.y, w, h);
        else
        {
            auto rc = RECT(p.x, p.y, p.x + w, p.y + h);
            fill!BR(rc);
        }
    }

    ///
    SIZE calcTextSize(const(wchar)[] str, HFONT f = null)
    {
        SIZE size;
        if (f !is null) f = SelectObject(_payload, f);
        GetTextExtentPoint32W(_payload, str.ptr, cast(int)str.length, &size);
        if (f !is null) f = SelectObject(_payload, f);
        return size;
    }

    /// TextOut を呼び出す。
    void text(string L = "C")(wstring str)
    {
        POINT p; MoveToEx(_payload, 0, 0, &p);
        text!L(str, p);
    }

    /// テキストがちょうど入る RECT を返す。
    RECT getTextRect(string L = "C")(in int x, in int y, wstring str)
    {
        enum LAYOUT
        {
            C = 0x0000,
            N = 0x0001,
            E = 0x0002,
            S = 0x0004,
            W = 0x0008,
        }
        enum l = {
            LAYOUT l;
            import std.ascii : toUpper;
            foreach (one; L) { switch(one.toUpper)
            {
                case        'N': l |= LAYOUT.N;
                break; case 'E': l |= LAYOUT.E;
                break; case 'S': l |= LAYOUT.S;
                break; case 'W': l |= LAYOUT.W;
                break; default:
            } }
            return l;
        }();

        auto s = calcTextSize(str);
        RECT rc;
        if      (l & LAYOUT.N) rc.top = y - s.cy;
        else if (l & LAYOUT.S) rc.top = y;
        else rc.top = y - s.cy / 2;

        if      (l & LAYOUT.E) rc.left = x;
        else if (l & LAYOUT.W) rc.left = x - s.cx;
        else rc.left = x - s.cx / 2;

        rc.right = rc.left + s.cx;
        rc.bottom = rc.top + s.cy;

        return rc;
    }

    /// ditto
    void text(string L = "C")(in int x, in int y, wstring str)
    {
        auto rc = getTextRect!L(x, y, str);
        text(rc, str);
    }
    /// ditto
    void text()(in auto ref RECT rc, wstring str)
    {
        TextOut(_payload, rc.left, rc.top, str.ptr, cast(int)str.length);
        MoveToEx(_payload, rc.right, rc.top, null);
    }

    /** 現在のペンで PolyDraw を呼び出す。
     * Assimptote っぽい書式で線を描く。
     * 直線 : 1, 2 -- 5, 6
     * ベジエ曲線 : 0, 0 -- 1, 2 .. 5, 6 -- 10, 10
     * ベジエ曲線(コントロールポイントを明示) : 0, 0 ~~ 1, 2 ~~ 5, 6 ~~ 10, 10
     */
    void line(string PATTERN)()
    {
///!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// BUG:
///   error LNK2001: unresolved external symbol
///   dmd2.068.2
///
///   1. -m64で
///   2. CTFE時に実行されるラムダ内で定義されている
///   3. 配列をメンバに持つ構造体の
///   4. 配列のconcatを行うと
///
        struct P{ Vector2f p; string t; }
///           ↑ 本当は ↓の mixin の中に入れたい。
        mixin({
            import std.string : join;
            import std.conv : to;
            import sworks.util.cached_buffer;

            string[] buf;

            @trusted @nogc pure nothrow
            static auto toVec(in POINT p)
            { return Vector2f(cast(float)p.x, cast(float)p.y); }
            @trusted @nogc pure nothrow
            static auto toPt(in Vector2f v)
            { return POINT(cast(int)v.x, cast(int)v.y); }

            P[] pos;
            bool circle = false;
            for (auto c = PATTERN.toCache; !c.empty;)
            {
                P p;
                c.stripLeftWhite;
                if (c.empty) break;
                switch(c.peek(2))
                {
                    case        "..": p.t = "AUTOBEZIER"; c.popFront(2);
                    break; case "--": p.t = "PT_LINETO"; c.popFront(2);
                    break; case "~~": p.t = "PT_BEZIERTO"; c.popFront(2);
                    break; default: p.t = "PT_MOVETO";
                }
                c.stripLeftWhite;
                if (c.empty)
                {
                    if (0 < pos.length)
                    { p.p = pos[0].p; circle = true; }
                    else break;
                }
                else p.p = toVec(c.toLONGSas!POINT);
                pos ~= p;
            }

            // Bezierのコントロールポイントの準備
            Vector2f pp, pd; // 1個前の場所と、接線方向

            // 最初だけは特別に準備する。
            if (0 < pos.length && pos[0].t == "AUTOBEZIER") // 最初はむり。
                pos[0].t = "PT_MOVETO";

            // 循環する場合の最初。
            if (circle && 1 < pos.length)
            {
                if      ("AUTOBEZIER" == pos[$-1].t)
                    pd = (pos[1].p - pos[$-2].p).normalizedVector;
                else if ("PT_LINETO" == pos[$-1].t)
                    pd = (pos[$-1].p - pos[$-2].p).normalizedVector;
            }
            if (0 < pos.length) pp = pos[0].p;

            for (size_t i = 1; i < pos.length; ++i) // 0 はとばす。
            {
                if      ("PT_MOVETO" == pos[i].t)
                { pd = Vector2f(); pp = pos[i].p; continue; }

                if ("AUTOBEZIER" != pos[i].t)
                {
                    pd = (pos[i].p - pp).normalizedVector;
                    pp = pos[i].p;
                    continue;
                }

                auto dir2 = Vector2f(0, 0);
                if      (i+1 < pos.length)
                {
                    if      ("AUTOBEZIER" == pos[i+1].t)
                        dir2 = (pos[i+1].p - pp).normalizedVector;
                    else if ("PT_MOVETO" != pos[i+1].t)
                        dir2 = (pos[i+1].p - pos[i].p).normalizedVector;
                }
                else if (circle && pos[1].t != "PT_MOVETO")
                    dir2 = (pos[1].p - pos[0].p).normalizedVector;

                auto p32 = pos[i].p - pp;
                auto dot1 = pd.dot(p32) * 0.6;
                auto dot2 = dir2.dot(p32) * 0.6;
                auto l = p32.length;

                pos[i].t = "PT_BEZIERTO";
                pos = pos[0..i]
                    ~ [P(pp + pd * (dot2<=0?l:dot2), "PT_BEZIERTO"),
                       P(pos[i].p - dir2 * (dot1<=0?l:dot1), "PT_BEZIERTO")]
                    ~ pos[i..$];
            }


            auto buf2 = new string[pos.length];
            foreach (i, one; pos) buf2[i] = toPt(one.p).to!string;
            buf ~= ["auto pos = [", buf2.join(","), "];"];

            foreach (i, one; pos) buf2[i] = one.t;
            buf ~= ["auto types = cast(BYTE[])[", buf2.join(","), "];",
                    "PolyDraw(_payload, pos.ptr, types.ptr, ",
                    pos.length.to!string, ");"];
            return buf.join;
        }());
    }

    /// PATTERN で PolyDraw を定義し、現在のブラシで塗り潰す。
    void fill(string PATTERN)()
    {
        BeginPath(_payload);
        line!PATTERN();
        EndPath(_payload);
        FillPath(_payload);
    }


    ///
    void blitTo()(Dc dst, in auto ref RECT r, DWORD dwRop = SRCCOPY)
    {
        BitBlt(dst.ptr, r.left, r.top, r.right - r.left, r.bottom - r.top,
               _payload, 0, 0, dwRop);
    }
}

/// 3Dっぽい影のついたウィンドウ色に塗る。
void fill3D(Dc dc, int W, int H)
{
    dc.fill!"3DDKSHADOW"(0, 0, W, 1);
    dc.fill!"3DDKSHADOW"(0, 1, 1, H);

    dc.fill!"3DHILIGHT"(1, 1, W-3, 2);
    dc.fill!"3DHILIGHT"(1, 3, 2, H-5);

    dc.fill!"3DFACE"(3, 3, W-5, H-5);

    dc.fill!"3DDKSHADOW"(0, H-2, W-2, 2);
    dc.fill!"3DDKSHADOW"(W-2, 0, 2, H);
}
/// 凹んでる。
void fill3DInv(Dc dc, int W, int H)
{
    dc.fill!"3DDKSHADOW"(0, 0, W, 3);
    dc.fill!"3DDKSHADOW"(0, 3, 3, H-3);

    dc.fill!"3DFACE"(3, 3, W-4, H-4);

    dc.fill!"3DDKSHADOW"(W-1, 3, 1, H);
    dc.fill!"3DDKSHADOW"(3, H-1, W-3, 1);
}

//------------------------------------------------------------------------------
/** 線形グラデーションで塗る。

x, y, w, h の範囲が少くとも塗り潰される。むしろそれよりハミ出て塗り
潰される。→ クリップして使ってね。
point1 から point2 の間がグラデーションになり、それの外側は端の色となる。
GradientStop.offset = 0 のとき point1 の位置を表し、
       〃           = 1 のとき point2 の位置を表す。

$(LINK #sworks.gdi.alphaBlit)関数のソースとして使う場合は stops に指定する
色のアルファ値を反転させておく必要がある。
**/
void fillLinearGradient(Dc dc, int x, int y, int w, int h,
                        POINT point1, POINT point2,
                        GradientStop[] stops)
{
    // 四隅の座標。
    auto lt = Vector2f(x, y);
    auto rt = Vector2f(x+w, y);
    auto lb = Vector2f(x, y+h);
    auto rb = Vector2f(x+w, y+h);
    auto pos1 = Vector2f(point1.x, point1.y);
    auto pos2 = Vector2f(point2.x, point2.y);

    // グラデーションの方向のベクトル
    auto v0 = pos2 - pos1;
    auto v = v0.normalizedVector;
    // グラデーションに垂直な方向
    auto v2 = Vector2f(-v.y, v.x);

    // 指定範囲をハミ出て塗る為にそれぞれの軸への射影を求めている。
    // グラデーション方向に垂直な軸への影
    float t, minS =0, maxS = 0;
    t = v.cross(lt - pos1);
    if      (t < minS) minS = t;
    else if (maxS < t) maxS = t;
    t = v.cross(rt - pos1);
    if      (t < minS) minS = t;
    else if (maxS < t) maxS = t;
    t = v.cross(lb - pos1);
    if      (t < minS) minS = t;
    else if (maxS < t) maxS = t;
    t = v.cross(rb - pos1);
    if      (t < minS) minS = t;
    else if (maxS < t) maxS = t;

    // グラデーション方向への影
    float minC = 0, maxC = 0;
    t = v.dot(lt - pos1);
    if      (t < minC) minC = t;
    else if (maxC < t) maxC = t;
    t = v.dot(rt - pos1);
    if      (t < minC) minC = t;
    else if (maxC < t) maxC = t;
    t = v.dot(lb - pos1);
    if      (t < minC) minC = t;
    else if (maxC < t) maxC = t;
    t = v.dot(rb - pos1);
    if      (t < minC) minC = t;
    else if (maxC < t) maxC = t;

    // 一時的に使うのん
    Vector2f vt;
    auto v2min = v2 * minS;
    auto v2max = v2 * maxS;
    auto distance = pos1.distance(pos2);

    auto l = stops.length + (minC < 0 ? 1 : 0) + (distance < maxC ? 1 : 0);
    auto pos = new Vector2f[l*2];
    size_t posi = 0;
    auto col = new uint[l];
    size_t coli = 0;

    // グラデーション開始位置よりも範囲の方が広い。
    if (minC < 0)
    {
        vt = pos1 + v * minC;
        pos[posi++] = vt + v2min;
        pos[posi++] = vt + v2max;
        col[coli++] = stops[0].color;
    }

    // グラデーション
    for (size_t i = 0; i < stops.length; ++i)
    {
        vt = pos1 + v0 * stops[i].offset;
        pos[posi++] = vt + v2min;
        pos[posi++] = vt + v2max;
        col[coli++] = stops[i].color;
    }

    // グラデの最後よりも範囲が広い場合。
    if (distance < maxC)
    {
        vt = pos1 + v * maxC;
        pos[posi++] = vt + v2min;
        pos[posi++] = vt + v2max;
        col[coli++] = stops[$-1].color;
    }

    // 塗り潰し。
    fillLinearGradient(dc.ptr, pos, col);
}
/// ditto
struct GradientStop
{
    float offset;
    COLORREF color;
}
//
private void fillTRIVERTEX(float x, float y, uint color, out TRIVERTEX t)
{
    t.x = cast(int)x;
    t.y = cast(int)y;
    t.Red = GetRValue(color) << 8;
    t.Green = GetGValue(color) << 8;
    t.Blue = GetBValue(color) << 8;
    t.Alpha = (color >> 16) & 0xff00;
}
//
private void fillLinearGradient(HDC hdc, Vector2f[] pos, uint[] col)
{
    assert(pos.length == col.length * 2);

    auto v = new TRIVERTEX[pos.length];
    for (size_t i = 0; i < v.length; ++i)
        fillTRIVERTEX(pos[i].x, pos[i].y, col[i>>1], v[i]);
    auto t = new GRADIENT_TRIANGLE[pos.length - 2];
    for (uint i = 0; i < t.length; i+=2)
    {
        t[i] = GRADIENT_TRIANGLE(i, i+1, i+2);
        t[i+1] = GRADIENT_TRIANGLE(i+2, i+1, i+3);
    }

    GradientFill(hdc, v.ptr, cast(uint)v.length, t.ptr, cast(uint)t.length,
                 GRADIENT_FILL_TRIANGLE);
}


/*
pos[0] は中心。
pos[1..$] は、内側から1周ずつ格納されているとする。

col[0] は中心の色
col[$-1] は外側の色。
*/
private void _fillRadialGradient(HDC hdc, Vector2f[] pos, uint[] col)
{
    assert(1 < pos.length);
    assert(1 < col.length);
    // 1周を何分割しているか。
    auto div = cast(uint)((pos.length-1) / (col.length - 1));
    auto v = new TRIVERTEX[pos.length];
    // 中心
    fillTRIVERTEX(pos[0].x, pos[0].y, col[0], v[0]);
    for (size_t i = 1; i < v.length; ++i)
        fillTRIVERTEX(pos[i].x, pos[i].y, col[(i-1)/div+1], v[i]);

    auto t = new GRADIENT_TRIANGLE[div + div * 2 * (col.length-2)];

    // 最初の一周
    for (uint i = 0; i < div-1; ++i)
        t[i] = GRADIENT_TRIANGLE(0, i+1, i+2);
    t[div-1] = GRADIENT_TRIANGLE(0, div, 1); // 最後の一角

    // 残りの周
    for (uint i = 0; i < col.length-2; ++i)
    {
        for (uint j = 0; j < div-1; ++j)
        {
            t[div + i * div * 2 + j*2]
                = GRADIENT_TRIANGLE(1+i*div+j,
                                    1+(i+1)*div+j,
                                    1+(i+1)*div+j+1);
            t[div + i * div * 2 + j*2 + 1]
                = GRADIENT_TRIANGLE(1+i*div+j,
                                    1+(i+1)*div+j+1,
                                    1+i*div+j+1);
        }

        // 最後の1角
        t[div + (i+1) * div * 2 - 2]
            = GRADIENT_TRIANGLE(1+(i+1)*div-1,
                                1+(i+2)*div-1,
                                1+(i+1)*div);
        t[div + (i+1) * div * 2 - 1]
            = GRADIENT_TRIANGLE(1+(i+1)*div-1,
                                1+i*div,
                                1+(i+1)*div);
    }

    // 塗り潰し
    GradientFill(hdc, v.ptr, cast(uint)v.length, t.ptr, cast(uint)t.length,
                 GRADIENT_FILL_TRIANGLE);
}


//------------------------------------------------------------------------------
/** 円形グラデーションで塗る。

x, y, w, h の範囲が少くとも塗り潰される。むしろそれよりハミ出て塗り
潰される。→ クリップして使ってね。
largeCenter から radius の間がグラデーションになり、
それの外側は端の色となる。

GradientStop.offset = 0 のとき、center の位置を表し、
       〃           = 1 のとき、center から radius の位置を表す。

Params:
N           = 円を何分割するか。
center      = グラデーションの中心。
largeCenter = グラデーションの最大円の中心。
radius      = グラデーションの最大円の半径。
transform   = ようわからん。最後に掛ける。

Ref:
$(LINK http://www.w3.org/TR/SVG/pservers.html#RadialGradientElementGradientTransformAttribute)
**/
void fillRadialGradient(int N)(Dc dc, int x, int y, int w, int h,
                               POINT center, POINT largeCenter, int radius,
                               ref Matrix3f transform,
                               GradientStop[] stops)
{
    assert(2 <= stops.length);
    // 塗り潰しの最大半径を求める。
    float maxRadius = radius;
    auto lC = Vector2f(largeCenter.x, largeCenter.y);
    auto temp = Vector2f(x, y);
    auto dist = lC.distance(temp);
    if (maxRadius < dist) maxRadius = dist;
    temp = Vector2f(x + w, y);
    dist = lC.distance(temp);
    if (maxRadius < dist) maxRadius = dist;
    temp = Vector2f(x, y + h);
    dist = lC.distance(temp);
    if (maxRadius < dist) maxRadius = dist;
    temp = Vector2f(x + w, y + h);
    dist = lC.distance(temp);
    if (maxRadius < dist) maxRadius = dist;

    // 一時オブジェクト
    auto gC = Vector2f(center.x, center.y);
    float smallRadius = 0, middleRadius = 0;
    float delta = DOUBLE_PI / N;
    Vector2f small1, small2, large1, large2;
    auto lgC = lC - gC;

    // グラデーションに使うやつ。
    TRIVERTEX[] v;
    GRADIENT_TRIANGLE[] t;

    // stop 位置とX軸からの角度で位置を得る。
    Vector2f getPos(float r, float rad)
    {
        auto v = Vector2f(radius, 0);
        v.rotate(rad);
        v += lgC;
        v *= r;
        v += gC;
        v = transform * v;
        return v;
    }

    //
    auto col = new uint[stops.length + (radius < maxRadius ? 1 : 0)];
    auto pos = new Vector2f[1 + (stops.length-1) * N
                           + (radius < maxRadius ? N : 0)];

    // 中心
    pos[0] = gC;
    col[0] = stops[0].color;

    for (size_t i = 1; i < stops.length; ++i)
    {
        for (size_t j = 0; j < N; ++j)
            pos[1+(i-1)*N+j] = getPos(stops[i].offset, delta * j);
        col[i] = stops[i].color;
    }
    if (radius < maxRadius)
    {
        radius = cast(int)maxRadius;
        for (size_t j = 0; j < N; ++j)
            pos[$-N+j] = getPos(1, delta * j);
        col[$-1] = stops[$-1].color;
    }

    // 塗り潰し。
    _fillRadialGradient(dc.ptr, pos, col);
}

//------------------------------------------------------------------------------
/** src bitmap のアルファチャンネル使わないタイプの半透明合成

$(LINK2 https://msdn.microsoft.com/en-us/library/windows/desktop/dd183351%28v=vs.85%29.aspx, AlphaBlend())用

Params:
alpha = src 全体に適用されるアルファ値。[0, 1]の範囲で、
        0 = 透明
        1 = 不透明
        で指定する。
**/
BOOL alphaBlit(HDC dst, int dstX, int dstY, int dstW, int dstH,
               HDC src, int srcX, int srcY, float alpha)
{
    return AlphaBlend(dst, dstX, dstY, dstW, dstH, src, srcX, srcY, dstW, dstH,
         BLENDFUNCTION(AC_SRC_OVER, 0, cast(BYTE)(0xff * alpha), 0));
}



/// suger
HBITMAP newDIB(HDC dc, int w, int h, ubyte bitCount, out ubyte* pbits)
{
    BITMAPINFO bmi;
    with (bmi.bmiHeader)
    {
        biSize = BITMAPINFO.sizeof;
        biWidth = w;
        biHeight = h;
        biPlanes = 1;
        biBitCount = bitCount;
        biCompression = BI_RGB;
    }
    void* pb;
    auto r = CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, &pb, null, 0);
    pbits = cast(ubyte*)pb;
    return r;
}
/// ditto
HBITMAP newDIB(HDC dc, int w, int h, ubyte bitCount)
{
    BITMAPINFO bmi;
    with (bmi.bmiHeader)
    {
        biSize = BITMAPINFO.sizeof;
        biWidth = w;
        biHeight = h;
        biPlanes = 1;
        biBitCount = bitCount;
        biCompression = BI_RGB;
    }
    void* pb;
    auto r = CreateDIBSection(dc, &bmi, DIB_RGB_COLORS, &pb, null, 0);
    return r;
}

// ※ 実行後、srcの中身は変になってます。
BOOL alphaMerge(HDC dst, int dstX, int dstY, int dstW, int dstH,
                HDC src, float alpha = 1.0, bool invert = false)
{
    GdiFlush();
    auto srcbmp = GetCurrentObject(src, OBJ_BITMAP);
    BITMAP srcbm; GetObject(srcbmp, BITMAP.sizeof, &srcbm);
    assert(srcbm.bmBitsPixel == 32);
    auto pbits = cast(ubyte*)srcbm.bmBits;
    auto stride = srcbm.bmWidthBytes;
    size_t wh = srcbm.bmWidth * srcbm.bmHeight * 4;
    ubyte inv = invert ? 0xff : 0;

    for (size_t p = 0; p < wh; p+=4)
    {
        pbits[p+3] ^= inv;
        auto af = (cast(float)pbits[p+3]) / 255f;
        pbits[p]   = cast(ubyte)((cast(float)pbits[p]) * af);
        pbits[p+1] = cast(ubyte)((cast(float)pbits[p+1]) * af);
        pbits[p+2] = cast(ubyte)((cast(float)pbits[p+2]) * af);
    }
    auto r = AlphaBlend(dst, dstX, dstY, dstW, dstH,
                        src, 0, 0, srcbm.bmWidth, srcbm.bmHeight,
                        BLENDFUNCTION(AC_SRC_OVER, 0,
                        cast(ubyte)(255f * alpha), AC_SRC_ALPHA));
    return r;
}

/** src 画像のピクセル毎のalpha値を使うタイプの半透明合成を行う。

NOTICE:
  proc 内で 引数のデヴァイスコンテキストに画像を書き込む。
  この時、画像の alpha チャンネルは 0=不透明、255=透明とする。
  直感とは逆なので注意。

関数終了時の dst の alpha チャンネルは 0=透明、255=不透明である。

input 画像の alpha 値が反転しているのは何故かというと、
WIN32の多くの描画関数で、アルファ値に0以外を指定できないからである。
WHITENESS で BitBlt 関数を呼び出した場合は 0xffffffff で塗り潰される。
背景の透明部分を WHITENESS で塗り潰し、不透明部分を普通のペンやブラシで塗
ればうまくいく。

output画像の alpha チャンネルが input画像に対して反転するのは、関数内で呼
び出している $(LINK2 https://msdn.microsoft.com/en-us/library/windows/desktop/dd183351%28v=vs.85%29.aspx, AlphaBlend()関数)
の出力がそうなっているため。

**/
BOOL alphaBlit(HDC dst, int dstX, int dstY, int dstW, int dstH,
               void delegate(BitmapDc) proc, float alpha = 1.0)
{
    ubyte* pbits;
    auto src = BitmapDc(dst, dstW, dstH, 32, pbits);
    proc(src);
    auto r = alphaMerge(dst, dstX, dstY, dstW, dstH, src.ptr, alpha, true);
    src.clear;
    return r;
}
/// ditto
BOOL alphaBlit(HDC dst, int dstX, int dstY, int dstW, int dstH,
               void delegate(BitmapDc) proc, int srcW, int srcH,
               float alpha = 1.0)
{
    ubyte* pbits;
    auto src = BitmapDc(dst, srcW, srcH, 32, pbits);
    proc(src);
    auto r = alphaMerge(dst, dstX, dstY, dstW, dstH, src.ptr, alpha, true);
    src.clear;
    return r;
}

///
BOOL alphaStretch(HDC src, int newW, int newH, bool invert = false)
{
    auto dst = BitmapDc(src, newW, newH, 32);
    SetStretchBltMode(dst.ptr, HALFTONE);
    auto r = alphaMerge(dst.ptr, 0, 0, newW, newH, src, 1.0, invert);
    DeleteObject(SelectObject(src, dst.dumpClear));
    return r;
}

///
void alphaBlur(HDC src, float strength)
{
    assert(1 < strength);
    BITMAP srcbm;
    GetObject(GetCurrentObject(src, OBJ_BITMAP), BITMAP.sizeof, &srcbm);
    assert(srcbm.bmBitsPixel == 32);


    auto w = cast(int)(srcbm.bmWidth / strength);
    auto h = cast(int)(srcbm.bmHeight / strength);
    auto dst = BitmapDc(src, w, h, 32);
    SetStretchBltMode(dst.ptr, HALFTONE);
    alphaMerge(dst.ptr, 0, 0, w, h, src);

    BitBlt(src, 0, 0, srcbm.bmWidth, srcbm.bmHeight, null, 0, 0, BLACKNESS);
    SetStretchBltMode(src, HALFTONE);
    alphaMerge(src, 0, 0, srcbm.bmWidth, srcbm.bmHeight, dst.ptr);
    dst.clear;
}

/* アルファチャンネルを含む。1ピクセル 32bit。0xAABBGGRRのフォーマット。
alpha チャンネルは 0=不透明、255=透明とする。

Params:
W      = ボカシの幅
dst    = ボカされた画像が出力される。
         src と同じだけ確保されている必要がある。
src    = 1列目の該当ピクセルを指している。
         この関数では、src + num * stride までアクセスする。
stride = 次に読むピクセルまで何byte離れているか。
         4の時、横方向へのボカシになる。
         4*imageWidth の時、縦方向へのボカシになる。
num    = ピクセル数
*/
private void blurBoxA(ubyte* dst, ubyte* src,
                      in int W, in size_t stride, in int num) pure
{
    const int W2 = W>>1;
    float r = 0, g = 0, b = 0;
    int a, an;
    size_t j;
    float alpha, n = 0;

    for (int i = -W2; i < num; ++i)
    {
        // 右端の色を追加
        if (i+W2 < num)
        {
            j = (i+W2)*stride;

            alpha = 1 - src[j+3] / 255.0f;
            r += src[j] * alpha;
            g += src[j+1] * alpha;
            b += src[j+2] * alpha;
            a += src[j+3];
            n += alpha;
            ++an;
        }

        // 代入
        j = i * stride;
        if (0 < n && 0 <= i)
        {
            dst[j] = cast(ubyte)(r / n);
            dst[j+1] = cast(ubyte)(g / n);
            dst[j+2] = cast(ubyte)(b / n);
        }
        if (0 < an && 0 <= i)
        {
            dst[j+3] = cast(ubyte)(a / an);
        }

        // 左端の色を引く。
        if (W2 <= i)
        {
            j = (i-W2)*stride;

            alpha = 1 - src[j+3] / 255.0f;
            r -= src[j] * alpha;
            g -= src[j+1] * alpha;
            b -= src[j+2] * alpha;
            a -= src[j+3];
            n -= alpha;
            --an;
        }
    }
}
/* ditto
アルファチャンネルなし。1ピクセル24bit
*/
private void blurBox(ubyte* dst, ubyte* src,
                     in int W, in size_t stride, in int num) pure
{
    const int W2 = W>>1;
    int r = 0, g = 0, b = 0, n;
    size_t j;

    for (int i = -W2; i < num; ++i)
    {
        // 右端の色を追加
        if (i+W2 < num)
        {
            j = (i+W2)*stride;

            r += src[j];
            g += src[j+1];
            b += src[j+2];
            ++n;
        }

        // 代入
        if (0 < n && 0 <= i)
        {
            j = i * stride;
            dst[j] = cast(ubyte)(r / n);
            dst[j+1] = cast(ubyte)(g / n);
            dst[j+2] = cast(ubyte)(b / n);
        }

        // 左端の色を引く。
        if (W2 <= i)
        {
            j = (i-W2)*stride;

            r -= src[j];
            g -= src[j+1];
            b -= src[j+2];
            --n;
        }
    }
}

/** 画像をボカす。

入力／出力画像の alpha チャンネルは 0=不透明、255=透明とするので注意。
引数の BITMAP.bmBits にアクセスするため、この関数を呼ぶ前に
$(LINK2 https://msdn.microsoft.com/en-us/library/windows/desktop/dd144844%28v=vs.85%29.aspx, GdiFlush())を呼んでね。

参照:
$(LINK http://blog.ivank.net/fastest-gaussian-blur.html)

Params:
  bm  = ボカす画像。
        bmBitsPixelは 32 か 24 のみに対応。
  W   = サンプル数。
        2以上でボケます。
  N   = ボカす回数。
        1で box blur
        2以上で pseudo gaussian blur。

一辺が W * N の矩形内に色が影響します。

Throws:
  bm.bmBitsPixel が 32、24 以外で assertion error。
**/
void blurImage(ref BITMAP bm, in uint W, in ubyte N)
{
    auto src = cast(ubyte*)bm.bmBits;
    auto w= bm.bmWidth;
    auto wb = bm.bmWidthBytes;
    auto h = bm.bmHeight;
    if      (32 == bm.bmBitsPixel)
    {
        ubyte* dst = (new ubyte[wb * h]).ptr;
        for (ubyte i = 0; i < N; ++i)
        {
            for (size_t y = 0; y < h; ++y)
                blurBoxA(dst+y*wb, src+y*wb, W, 4, w);
            for (size_t x = 0; x < w; ++x)
                blurBoxA(src+x*4, dst+x*4, W, wb, h);
        }
    }
    else if (24 == bm.bmBitsPixel)
    {
        auto dst = (new ubyte[wb * h]).ptr;
        for (ubyte i = 0; i < N; ++i)
        {
            for (size_t y = 0; y < h; ++y)
                blurBox(dst+y*wb, src+y*wb, W, 3, w);
            for (size_t x = 0; x < w; ++x)
                blurBox(src+x*3, dst+x*3, W, wb, h);
        }
    }
    else assert(0);
}

/** bm のアルファチャンネルを反転させる。

Exception:
  b.BitsPixel が32以外だったら assertion error.
**/
@nogc pure
void invertAlpha(ref BITMAP bm)
{
    assert(bm.bmBitsPixel == 32);

    auto buf = cast(uint*)bm.bmBits;
    auto stride = bm.bmWidthBytes >> 2;
    for (int y = 0; y < bm.bmHeight; ++y)
        for (int x = 0; x < bm.bmWidth; ++x)
            buf[y*stride+x] ^= 0xff000000;
}
// ditto
@nogc
void invertAlpha(Dc dc)
{
    BITMAP bm; dc.getBITMAP(bm);
    assert(bm.bmBitsPixel == 32);

    auto buf = cast(uint*)bm.bmBits;
    auto stride = bm.bmWidthBytes >> 2;
    for (int y = 0; y < bm.bmHeight; ++y)
        for (int x = 0; x < bm.bmWidth; ++x)
            buf[y*stride+x] ^= 0xff000000;
}


///
HBITMAP cloneBmp(HDC odc, HBITMAP bmp)
{
    BITMAP b; GetObject(bmp, BITMAP.sizeof, &b);

    auto sdc = CreateCompatibleDC(odc);
    auto ddc = CreateCompatibleDC(odc);
    auto dbmp = CreateCompatibleBitmap(odc, b.bmWidth, b.bmHeight);
    auto psbmp = SelectObject(sdc, bmp);
    auto pdbmp = SelectObject(ddc, dbmp);
    BitBlt(ddc, 0, 0, b.bmWidth, b.bmHeight, sdc, 0, 0, SRCCOPY);
    SelectObject(sdc, psbmp);
    SelectObject(ddc, pdbmp);
    DeleteObject(sdc);
    return dbmp;
}

/// alphaチャンネルからマスク画像を得る。
HBITMAP splitMask(Dc dc, bool invert = false)
{
    import std.conv : to;
    BITMAP srcbm; dc.getBITMAP(srcbm);
    auto src = cast(ubyte*)srcbm.bmBits;
    auto srcstride = srcbm.bmWidthBytes;
    auto w = srcbm.bmWidth;
    auto h = srcbm.bmHeight;
    assert (srcbm.bmBitsPixel == 32, srcbm.bmBitsPixel.to!string ~ " != 32");

    auto maskdc = BitmapDc(dc.ptr, w, h, 1);
    BITMAP maskbm; maskdc.getBITMAP(maskbm);
    auto mask = cast(ubyte*)maskbm.bmBits;
    auto maskstride = maskbm.bmWidthBytes;
    enum cols = [0x00000000, 0xffffffff];
    SetDIBColorTable(maskdc.ptr, 0, 2, cast(RGBQUAD*)cols.ptr);

    for (int y = 0; y < h; ++y)
    {
        for (int x = 0; x < w; ++x)
        {
            if ((0 == (src[y * srcstride + x * 4 + 3])) == invert)
                mask[y * maskstride + x / 8] |=
                    cast(ubyte)(1 << (7-(x % 8)));
        }
    }
    return maskdc.dumpClear;
}

//
void splitMask2(Dc dc, out HBITMAP _col, out HBITMAP _mask, bool invert = false)
{
    import std.conv : to;
    BITMAP srcbm; dc.getBITMAP(srcbm);
    auto src = cast(ubyte*)srcbm.bmBits;
    auto srcstride = srcbm.bmWidthBytes;
    auto w = srcbm.bmWidth;
    auto h = srcbm.bmHeight;
    assert (srcbm.bmBitsPixel == 32, srcbm.bmBitsPixel.to!string ~ " != 32");

    auto maskdc = BitmapDc(dc.ptr, w, h, 1);
    BITMAP maskbm; maskdc.getBITMAP(maskbm);
    auto mask = cast(ubyte*)maskbm.bmBits;
    auto maskstride = maskbm.bmWidthBytes;

    auto colordc = BitmapDc(dc.ptr, w, h, 24);
    BITMAP colorbm; colordc.getBITMAP(colorbm);
    auto color = cast(ubyte*)colorbm.bmBits;
    auto colorstride = colorbm.bmWidthBytes;

    auto trueside = invert ? 0 : 1;
    auto falseside = invert ? 1 : 0;

    for (int y = 0; y < h; ++y)
    {
        for (int x = 0; x < w; ++x)
        {
            mask[y * maskstride + x / 8] |= cast(ubyte)
                ((0xef < (src[y * srcstride + x * 4 + 3]))
                 ? trueside : falseside) << (x % 8);
            color[y * colorstride + x * 3 .. y * colorstride + x * 3 + 3] =
               src[y * srcstride + x * 4 .. y * srcstride + x * 4 + 3];
        }
    }
    _mask = maskdc.dumpClear;
    _col = colordc.dumpClear;
}

//------------------------------------------------------------------------------
/// BitBlt 用のラッパ
struct BitmapDc
{
    ///
    Dc dc;
    alias dc this;

    private HBITMAP _originalBmp;
    private int* _refCount;

    ///
    this(HDC originalDc, int w, int h)
    {
        dc = Dc(CreateCompatibleDC(originalDc));
        auto bmp = CreateCompatibleBitmap(originalDc, w, h);
        _originalBmp = SelectObject(dc.ptr, bmp);
        _refCount = (new int[1]).ptr;
    }

    ///
    this(HDC originalDc, int w, int h, ubyte bpp)
    {
        dc = Dc(CreateCompatibleDC(originalDc));
        auto bmp = newDIB(originalDc, w, h, bpp);
        _originalBmp = SelectObject(dc.ptr, bmp);
        _refCount = (new int[1]).ptr;
    }

    ///
    this(HDC originalDc, int w, int h, ubyte bpp, out ubyte* pbits)
    {
        dc = Dc(CreateCompatibleDC(originalDc));
        auto bmp = newDIB(originalDc, w, h, bpp, pbits);
        _originalBmp = SelectObject(dc.ptr, bmp);
        _refCount = (new int[1]).ptr;
    }

    ///
    this(HDC originalDc, HBITMAP bmp)
    {
        dc = Dc(CreateCompatibleDC(originalDc));
        _originalBmp = SelectObject(dc.ptr, bmp);
        _refCount = (new int[1]).ptr;
    }

    /**
    ビットマップの本体とその参照を使い分けることで、不要なメモリコピーを減らす。
    */
    @trusted pure nothrow
    int incRefCount()
    {
        ++(*_refCount);
        return (*_refCount);
    }

    ///
    @trusted @nogc pure nothrow
    bool opEquals(in BitmapDc d) const
    { return d.dc._payload is dc._payload; }

    ///
    @trusted @nogc pure nothrow
    bool opEquals(in Dc d) const
    { return d._payload is dc._payload; }

    ///
    SIZE size() @property
    { BITMAP b; getBITMAP(b); return SIZE(b.bmWidth+1, b.bmHeight+1); }

    ///
    void blitTo(Dc dst, int x, int y, DWORD dwRop = SRCCOPY)
    {
        auto s = size;
        BitBlt(dst.ptr, x, y, s.cx, s.cy, _payload, 0, 0, dwRop);
    }
    void blitTo(Dc dst, int x, int y, int w, int h, DWORD dwRop = SRCCOPY)
    {
        BitBlt(dst.ptr, x, y, w, h, _payload, 0, 0, dwRop);
    }


    ///
    void clear()
    {
        if (_refCount !is null && 0 < (*_refCount)) --(*_refCount);
        else
        {
            DeleteObject(SelectObject(dc.ptr, _originalBmp));
            dc.clear;
            _originalBmp = null;
            _refCount = null;
        }
    }

    ///
    HBITMAP dumpClear()
    {
        assert(_refCount is null || (*_refCount) == 0);
        auto bmp = SelectObject(dc.ptr, _originalBmp);
        dc.clear;
        _refCount = null;
        _originalBmp = null;
        return bmp;
    }

    ///
    void stretchTo()(Dc dst, in auto ref RECT r, DWORD dwRop = SRCCOPY)
    {
        BITMAP b; getBITMAP(b);
        if (r.right - r.left == b.bmWidth && r.bottom - r.top == b.bmHeight)
            BitBlt(dst.ptr, r.left, r.top, b.bmWidth, b.bmHeight,
                   dc.ptr, 0, 0, dwRop);
        else
            StretchBlt(dst.ptr, r.left, r.top,
                                r.right - r.left, r.bottom - r.top,
                       dc.ptr, 0, 0, b.bmWidth, b.bmHeight, dwRop);
    }
}

//==============================================================================
// 画像をくっつける。

/// くっつける元データの抽象型
interface IImageResource { SIZE size(Wnd); void clear(); }

/// 文字のくっつけるデータ
class TextResource : IImageResource
{
    wstring text; ///
    HFONT font; ///
    private SIZE _size;
    ///
    @trusted @nogc pure nothrow
    this(wstring t, HFONT f = null){ text = t; font = f; }
    //
    SIZE size(Wnd wnd)
    {
        if (_size.cx <= 0) _size = wnd.calcTextSize(text, font);
        return _size;
    }
    //
    void clear()
    {
        if (font !is null) DeleteObject(font);
        font = null;
        text = null;
        _size = SIZE(-1, -1);
    }
}

/// 画像のくっつけるデータ
class BmpResource : IImageResource
{
    HANDLE handle; ///
    private SIZE _size;
    ///
    @trusted @nogc pure nothrow
    this(HANDLE h){ handle = h; }
    //
    SIZE size(Wnd)
    {
        if (_size.cx <= 0)
        {
            BITMAP b; GetObject(handle, BITMAP.sizeof, &b);
            _size = SIZE(b.bmWidth, b.bmHeight);
        }
        return _size;
    }
    //
    void clear()
    {
        if (handle !is null) DeleteObject(handle);
        handle = null;
        _size = SIZE(-1, -1);
    }
}

/// 空白のくっつけるデータ
class SizeResource : IImageResource
{
    private SIZE _size;
    ///
    @trusted @nogc pure nothrow
    this(SIZE s){ _size = s; }
    @trusted @nogc pure nothrow
    SIZE size(Wnd) const { return _size; }
    void clear() { _size = SIZE(-1, -1); }
}

/// 塗りつぶしデータ
class FillResource : IImageResource
{
    RECT rect; ///
    HANDLE brush; ///
    ///
    this(int l, int t, int r, int b, HANDLE br = null)
    {
        rect = RECT(l, t, r, b);
        brush = br ? br : GetStockObject(BLACK_BRUSH);
    }
    this(in RECT r, HANDLE br = null)
    {
        rect = r;
        brush = br ? br : GetStockObject(BLACK_BRUSH);
    }
    //
    @trusted @nogc pure nothrow
    SIZE size(Wnd) const { return SIZE(0, 0); } // 占有する領域は 0
    //
    void clear()
    {
        if (brush) DeleteObject(brush);
        brush = null;
    }
}

/// 改行のくっつけるデータ
class LineBreakResource : IImageResource
{
    @trusted @nogc pure nothrow :
    this(){}
    SIZE size(Wnd){ return SIZE(0, 0); }
    void clear(){}
}

/// データの列びをどうするか
enum ALIGN
{
    LEFT   = 0x00, ///
    CENTER = 0x01, ///
    RIGHT  = 0x02, ///
    TOP    = 0x00, ///
    MIDDLE = 0x04, ///
    BOTTOM = 0x08, ///
    C      = CENTER | MIDDLE ///
}

/** 画像とか文字を一緒くたにして画像にする。
Params:
  size = 画像サイズを指定する。
         ただし、中身がこれより大きくなったら無視される。
**/
HANDLE combine(Wnd wnd, ALIGN al, HBRUSH bgBrush, SIZE size,
               IImageResource[] rcs...)
{
    import std.utf : toUTF16z;
    auto lineSizes = new SIZE[1];
    foreach (one; rcs) // 各行のサイズを計算
    {
        if (cast(LineBreakResource)one) { lineSizes ~= SIZE(0, 0); continue; }
        auto s = one.size(wnd);
        auto l = &lineSizes[$-1];
        l.cx += s.cx;
        if (l.cy < s.cy) l.cy = s.cy;
    }
    SIZE reqSize; // 全体のサイズ
    POINT ite;
    foreach (one; lineSizes) // 全体のサイズを計算
    {
        if (reqSize.cx < one.cx) reqSize.cx = one.cx;
        reqSize.cy += one.cy;
    }
    if (reqSize.cx < size.cx)
    {
        ite.x = (size.cx - reqSize.cx)/2;
        reqSize.cx = size.cx;
    }
    if (reqSize.cy < size.cy)
    {
        ite.y = (size.cy - reqSize.cy) / 2;
        reqSize.cy = size.cy;
    }
    foreach (one; rcs)
    {
        if (auto fr = cast(FillResource)one)
        {
            if (reqSize.cx < fr.rect.right) reqSize.cx = fr.rect.right;
            if (reqSize.cy < fr.rect.bottom) reqSize.cy = fr.rect.bottom;
        }
    }

    // デバイスコンテキストとか処理結果となるビットマップの準備
    auto odc = GetDC(wnd.ptr);
    auto srcDc = CreateCompatibleDC(odc);
    auto dstDc = CreateCompatibleDC(odc);
    auto odst = SelectObject(dstDc,
         CreateCompatibleBitmap(odc, reqSize.cx, reqSize.cy));
    ReleaseDC(wnd.ptr, odc);

    // 背景塗り潰し。文字の背景色をセット
    auto rc = RECT(0, 0, reqSize.cx, reqSize.cy);
    FillRect(dstDc, &rc, bgBrush);
    LOGBRUSH b; GetObject(bgBrush, LOGBRUSH.sizeof, &b);
    if (b.lbStyle == BS_SOLID) SetBkColor(dstDc, b.lbColor);
    else SetBkColor(dstDc, TRANSPARENT);


    bool linehead = true;
    size_t lineNum = 0;
    SIZE lineSize, s;
    foreach (one; rcs)
    {
        if (auto fr = cast(FillResource)one)
        {
            FillRect(dstDc, &fr.rect, fr.brush);
            continue;
        }

        if (linehead) // 行頭では左右の字揃えに合わせて空白を入れる。
        {
            ite.y += lineSize.cy;
            lineSize = lineSizes[lineNum];
            if      (al & ALIGN.CENTER)
                ite.x = (reqSize.cx - lineSize.cx)/2;
            else if (al & ALIGN.RIGHT)
                ite.x = reqSize.cx - lineSize.cx;
        }
        if (linehead = ((cast(LineBreakResource)one) !is null), linehead)
        { ++lineNum; continue; }

        s = one.size(wnd);
        int marginTop = 0; // 各アイテムの上下の揃えに合わせて空白を入れる。
        if      (al & ALIGN.MIDDLE)
            marginTop = (lineSize.cy - s.cy)/2;
        else if (al & ALIGN.BOTTOM)
            marginTop = lineSize.cy - s.cy;

        if      (auto tr = cast(TextResource)one)
        {
            if (tr.font !is null) tr.font = SelectObject(dstDc, tr.font);
            TextOut(dstDc, ite.x, ite.y + marginTop, tr.text.ptr,
                    cast(int)tr.text.length);
            if (tr.font !is null) tr.font = SelectObject(dstDc, tr.font);
        }
        else if (auto br = cast(BmpResource)one)
        {
            auto osrc = SelectObject(srcDc, br.handle);
            BitBlt(dstDc, ite.x, ite.y + marginTop, s.cx, s.cy,
                   srcDc, 0, 0, SRCCOPY);
            SelectObject(srcDc, osrc);
        }
        ite.x += s.cx;
    }

    auto result = SelectObject(dstDc, odst);
    DeleteObject(srcDc);
    DeleteObject(dstDc);
    return result;
}

//------------------------------------------------------------------------------
//
//
//
//------------------------------------------------------------------------------
///
struct UpdateTarget
{
    @trusted @nogc pure nothrow
    this(Wnd w){ _wnd = w; }

    @property @trusted @nogc pure nothrow
    auto ptr() inout { return &_target; }

    void update()
    { if (0 == IsRectEmpty(&_target)) _wnd.redraw(&_target); }

    void done() { SetRectEmpty(&_target); }

private:
    RECT _target;
    Wnd _wnd;
}


/**
常に 60fps で描き変えられるタイプではなく、必要に応じて随時 InvalidateRect
を呼び出すようなプログラムで使う。
_target を通じ、位置情報等が変わった時に更新領域を通知する。
**/
class RectUpdator
{
    private RECT* _target;
    private bool _v;
    private RECT _rc;

    /**
    Params:
      tr = 更新されるターゲット。
      v  = true -> 見えている。 false -> 見えていない。
      l  = left
      t  = top
      r  = right
      b  = bottom
    **/
    this(RECT* tr, bool v, int l = 0, int t = 0, int r = 0, int b = 0)
    {
        _target = tr;
        _v = v;
        _rc = RECT(l, t, r, b);
        unite;
    }

    protected void unite()
    { if (_v) { auto r = *_target; UnionRect(_target, &r, &_rc); } }

    ///
    @property @trusted @nogc pure nothrow
    bool visible() const { return _v; }

    ///
    @property @trusted @nogc pure nothrow
    const(RECT)* ptr() const { return &_rc; }
    ///
    @property @trusted @nogc pure nothrow
    ref auto rect() const { return _rc; }

    ///
    @property @trusted @nogc pure nothrow
    int left() const { return _rc.left; }
    ///
    @property @trusted @nogc pure nothrow
    int right() const { return _rc.right; }
    ///
    @property @trusted @nogc pure nothrow
    int top() const { return _rc.top; }
    ///
    @property @trusted @nogc pure nothrow
    int bottom() const { return _rc.bottom; }
    ///
    @property @trusted @nogc pure nothrow
    int width() const { return _rc.right - _rc.left; }
    ///
    @property @trusted @nogc pure nothrow
    int height() const { return _rc.bottom - _rc.top; }

    ///
    void set(int l, int t, int r, int b)
    {unite; _rc = RECT(l, t, r, b); unite; }
    ///
    void opAssign()(in auto ref RECT r)
    { unite; _rc = r; unite; }
    ///
    void zero()
    { hide; SetRectEmpty(&_rc); }

    ///
    void show()
    { if (!_v) {_v = true; unite;} }

    ///
    void hide()
    { if (_v) {unite; _v = false; } }

    ///
    bool hits(int x, int y) const
    { return _v && 0 != PtInRect(&_rc, POINT(x, y)); }
}


//------------------------------------------------------------------------------
///
class BmpRect : RectUpdator
{
    private BitmapDc _bmp;

    ///
    this(RECT* t, BitmapDc bmp, bool v = false, int x = 0, int y = 0)
    {
        assert(!bmp.empty);
        _bmp = bmp;
        auto s = _bmp.size;
        super(t, v, x, y, x + s.cx, y + s.cy);
    }

    ///
    @property @trusted @nogc pure nothrow
    auto dc() inout { return _bmp.dc; }

    ///
    void setCenterX(int x)
    {
        auto w2 = (right - left)/2;
        RectUpdator.set(x - w2, top, x + w2, bottom);
    }

    ///
    void setCenterY(int y)
    {
        auto h2 = (bottom - top)/2;
        RectUpdator.set(left, y - h2, right, y + h2);
    }

    ///
    void set(int x, int y)
    { RectUpdator.set(x, y, x + right - left, y + bottom - top); }

    ///
    void set(BitmapDc b)
    {
        if (_bmp == b) return;
        _bmp = b;
        auto s = b.size;
        auto dw2 = (s.cx - (right - left)) / 2;
        auto dh2 = (s.cy - (bottom - top)) / 2;
        RectUpdator.set(left - dw2, top - dh2, right + dw2, bottom + dh2);
    }

    ///
    void set(BitmapDc b, int x, int y)
    {
        assert(!b.empty);
        if (_bmp == b) return;
        _bmp = b;
        auto s = b.size;
        RectUpdator.set(x, y, x + s.cx, y + s.cy);
    }

    ///
    void blitTo(Dc dst, DWORD dwRop = SRCCOPY)
    {
        if (visible)
            BitBlt(dst.ptr, left, top, right - left, bottom - top,
                   _bmp.ptr, 0, 0, dwRop);
    }

    ///
    void stretchTo()(Dc dst, in auto ref RECT rc, DWORD dwRop = SRCCOPY)
    {
        if (visible)
            StretchBlt(dst.ptr, rc.left, rc.top,
                                rc.right - rc.left, rc.bottom - rc.top,
                       _bmp.ptr, left, top,
                                 right - left, bottom - top, dwRop);
    }

    ///
    void clear(){ _bmp.clear; }
}

//------------------------------------------------------------------------------
///
class BrushRect : RectUpdator
{
    private HBRUSH _brush;
    ///
    this(RECT* t, bool v, ubyte r, ubyte g, ubyte b)
    {
        super(t, v);
        _brush = CreateSolidBrush(RGB(r, g, b));
    }
    ///
    void clear(){ if (_brush) DeleteObject(_brush); _brush = null; }

    ///
    void blitTo(Dc dst)
    { if (visible && 0 == IsRectEmpty(ptr)) dst.fill(rect, _brush); }
}

//------------------------------------------------------------------------------
///
class TextRect : RectUpdator
{
    private wstring _text;
    protected COLORREF _color;
    protected COLORREF _bk;

    ///
    this(RECT* t, bool v, wstring txt = null, COLORREF c = RGB(0, 0, 0),
         COLORREF bk = RGB(255, 255, 255))
    { super(t, v); _text = txt; _color = c; _bk = bk; }
    ///
    this(RECT* t, bool v, COLORREF c, COLORREF bk = RGB(255, 255, 255))
    { super(t, v); _color = c; _bk = bk; }

    override protected void unite()
    {
        if (_v)
        {
            auto r1 = *_target;
            auto r2 = RECT(left-5, top-5, right+5, bottom+5);
            UnionRect(_target, &r1, &r2);
        }
    }

    ///
    @property @trusted @nogc pure nothrow
    wstring text() const { return _text; }

    ///
    void set(wstring t){ _text = t; }

    ///
    void set(string L = "C")(Wnd w, int x, int y)
    {
        auto rc = w.dc(dc => dc.getTextRect!L(x, y, _text));
        RectUpdator.opAssign(rc);
    }

    ///
    void set(string L = "C")(Wnd w, wstring t, int x, int y)
    {
        _text = t;
        auto rc = w.dc(dc => dc.getTextRect!L(x, y, _text));
        RectUpdator.opAssign(rc);
    }

    ///
    void blitTo(Dc dc)
    {
        if (visible)
        {
            COLORREF pc, bc;
            pc = SetTextColor(dc.ptr, _color);
            bc = SetBkColor(dc.ptr, _bk);
            dc.text(rect, _text);
            SetTextColor(dc.ptr, pc);
            SetBkColor(dc.ptr, bc);
        }
    }
}

//------------------------------------------------------------------------------
/**
mouseMove を呼び出すことでマウスホバーで絵が変わるようになる。
**/
class HoverRect : BmpRect
{
    private BitmapDc _ndc, _adc;

    ///
    this(RECT* t, BitmapDc n, BitmapDc a, bool v = false, int x = 0, int y = 0)
    {
        assert(!n.empty); assert(!a.empty);
        _ndc = n; _adc = a;
        super(t, n, v, x, y);
    }

    ///
    bool mouseMove(int x, int y)
    {
        if      (!visible) return false;
        else if (hits(x, y))
        {
            if (dc != _adc) set(_adc);
            return true;
        }
        else
        {
            if (dc != _ndc) set(_ndc);
            return false;
        }
    }

    ///
    void setActive(){ if (dc != _adc) set(_adc); }
    ///
    void setNormal(){ if (dc != _ndc) set(_ndc); }
    ///
    @property @trusted @nogc pure nothrow
    bool isActive() const { return dc != _ndc; }

    ///
    void change(BitmapDc n, BitmapDc a)
    {
        auto f = isActive;
        _ndc = n; _adc = a;
        if (f) setActive;
        else setNormal;
    }

    //
    override void hide()
    { setNormal; super.hide; }

    //
    override void clear() { _ndc.clear; _adc.clear; _bmp = _ndc; }
}

//------------------------------------------------------------------------------
/// 普通、ホバー、押下の3状態がある。
class S3Rect : HoverRect
{
    private BitmapDc _ddc;

    ///
    this(RECT* t, BitmapDc n, BitmapDc a, BitmapDc d, bool v = false,
         int x = 0, int y = 0)
    {
        assert(!d.empty);
        super(t, n, a, v, x, y);
        _ddc = d;
    }

    ///
    override
    bool mouseMove(int x, int y)
    {
        if     (hits(x, y))
        {
            if (!isActive) setActive;
            return true;
        }
        else if (visible)
        {
            if (isActive) setNormal;
        }
        return false;
    }


    ///
    void setDown(){ if (dc == _adc) set(_ddc); }
    ///
    @property @trusted @nogc pure nothrow
    bool isDown() const { return dc == _ddc; }

    ///
    void change(BitmapDc n, BitmapDc a, BitmapDc d)
    {
        auto f = isDown;
        super.change(n, a);
        _ddc = d;
        if (f) setDown;
    }

    ///
    override void clear(){ super.clear; _ddc.clear; }
}

//------------------------------------------------------------------------------
/// マウスホバーで色が変わる文字。
class HoverText : TextRect
{
    private COLORREF _normal, _active;

    ///
    this(RECT* t, bool v, COLORREF nc = RGB(150, 150, 150),
                         COLORREF ac = RGB(0, 0, 0))
    { super(t, v, nc); _normal = nc; _active = ac; }

    ///
    void setActive()
    { if (_color != _active) { _color = _active; unite; }}
    ///
    void setNormal()
    { if (_color != _normal) { _color = _normal; unite; }}
    ///
    void mouseMove(int x, int y)
    { if (hits(x, y)) setActive; else setNormal; }
}

BitmapDc readyBitmap(string PATH, string BG_COLOR, string COLOR)
    (HDC dc, int W, int H, bool isLine = false)
{
    auto ret = BitmapDc(dc, W, H);
    with (ret.dc)
    {
        fill!BG_COLOR(0, 0, W, H);
        selectBrush!COLOR;
        if (isLine) line!PATH;
        else fill!PATH;
    }
    return ret;
}

/** マウスホバーで灰色から黒に色が変わるボタン

中身の画像をstatic変数で共用している為、インスタンス毎のclearではなく、
clarAllを呼び出してください。
**/
class THoverButton(int W, int H, string PATH,
                   string BG_COLOR = "3DFACE",
                   string N_COLOR = "LTGRAY",
                   string A_COLOR = "BLACK") : S3Rect
{
    private static BitmapDc _normal, _hover, _down;
    private static void ready(Wnd wnd)
    {
        if (!_normal.empty) return;
        wnd.dc((dc)
        {
            _normal = readyBitmap!(PATH, BG_COLOR, N_COLOR)(dc.ptr, W, H);
            _hover = readyBitmap!(PATH, BG_COLOR, A_COLOR)(dc.ptr, W, H);
            _down = readyBitmap!(PATH, BG_COLOR, A_COLOR)(dc.ptr, W, H, true);
        });
    }

    alias ONCLICK = bool delegate();
    private ONCLICK _onClick;

    ///
    static void clearAll()
    {
        _normal.clear;
        _hover.clear;
        _down.clear;
    }

    ///
    this(Wnd wnd, RECT* ur, ONCLICK dg, bool v = false, int x = 0, int y = 0)
    {
        ready(wnd);
        super(ur, _normal, _hover, _down, v, x, y);
        _onClick = dg;
    }

    /// 呼び出してもなにも起きない。clearAllで本当に解放される。
    @trusted @nogc pure nothrow
    override void clear(){}

    /// ヒットしてたらtrue
    bool lDown(int x, int y)
    {
        bool f;
        if      (hits(x, y)) { setDown; f = true; }
        else if (visible) setNormal;
        return f;
    }

    /// クリックが処理されたら true。ヒットと関係ないので注意。
    bool lUp(int x, int y)
    {
        bool f;
        if (hits(x, y))
        {
            if (isDown && _onClick !is null) f = _onClick();
            setActive;
        }
        else setNormal;
        return f;
    }
}

/**
*/
class T2StateSwitch(int W, int H, string PATH_ON, string PATH_OFF,
                    string BG_COLOR = "3DFACE",
                    string N_COLOR = "LTGRAY",
                    string A_COLOR = "BLACK") : S3Rect
{
    alias ONCLICK = bool delegate(bool);

    static void clearAll()
    {
        _onNormal.clear; _onHover.clear; _onDown.clear;
        _offNormal.clear; _offHover.clear; _offDown.clear;
    }

    this(Wnd wnd, RECT* ur, ONCLICK dg, bool v = false, int x = 0, int y = 0)
    {
        ready(wnd);
        super(ur, _offNormal, _offHover, _offDown, v, x, y);
        _onClick = dg;
    }

    @trusted @nogc pure nothrow override
    void clear(){}

    bool lDown(int x, int y)
    {
        bool f;
        if      (hits(x, y)) { setDown; f = true; }
        else if (visible) setNormal;
        return f;
    }

    bool lUp(int x, int y)
    {
        bool f;
        if (hits(x, y))
        {
            _isOn = !_isOn;
            if (isDown && _onClick !is null) f = _onClick(_isOn);
            if (_isOn) change(_onNormal, _onHover, _onDown);
            else change(_offNormal, _offHover, _offDown);
            setActive;
        }
        else setNormal;
        return f;
    }

    @property @trusted @nogc pure nothrow
    bool isOn() const { return _isOn; }

private:
    ONCLICK _onClick;
    bool _isOn;
static:
    BitmapDc _onNormal, _onHover, _onDown, _offNormal, _offHover, _offDown;
    void ready(Wnd wnd)
    {
        if (!_onNormal.empty) return;
        wnd.dc((dc)
        {
            _onNormal = readyBitmap!(PATH_ON, BG_COLOR, N_COLOR)(dc.ptr, W, H);
            _onHover = readyBitmap!(PATH_ON, BG_COLOR, A_COLOR)(dc.ptr, W, H);
            _onDown = readyBitmap!(PATH_ON, BG_COLOR, A_COLOR)
                (dc.ptr, W, H, true);
            _offNormal = readyBitmap!(PATH_OFF, BG_COLOR, N_COLOR)
                (dc.ptr, W, H);
            _offHover = readyBitmap!(PATH_OFF, BG_COLOR, A_COLOR)(dc.ptr, W, H);
            _offDown = readyBitmap!(PATH_OFF, BG_COLOR, A_COLOR)
                (dc.ptr, W, H, true);
        });
    }
}


//------------------------------------------------------------------------------
///
struct SliderStop
{
    int value; ///
    private HoverText _text;
}

/// スライダーコントール。縦横兼用部分。
class VHSlider(bool isV)
{
    import std.algorithm : max, min;
    import sworks.win32.gdi;

    /// '_L' is 'Long side'. '_S' is 'Short side'.
    protected enum
    {
        THUMB_L = 20,
        THUMB_S = 10,
        SLIT_S = 4,
    }

    static if (isV)
    {
        protected alias THUMB_W = THUMB_L; ///
        protected alias THUMB_H = THUMB_S; ///
        protected alias SLIT_W = SLIT_S;   ///
        protected alias SLIT_H = _slit_length; ///
    }
    else
    {
        protected alias THUMB_W = THUMB_S; ///
        protected alias THUMB_H = THUMB_L; ///
        protected alias SLIT_H = SLIT_S;   ///
        protected alias SLIT_W = _slit_length; ///
    }

    ///
    protected static BitmapDc _thumbDc;
    ///
    static BitmapDc ready(Wnd wnd)
    {
        if (!_thumbDc.empty) return _thumbDc;
        wnd.dc((dc)
        {
            _thumbDc = BitmapDc(dc.ptr, THUMB_W, THUMB_H);
            _thumbDc.fill3D(THUMB_W, THUMB_H);
        });
        return _thumbDc;
    }
    ///
    static void clearAll() { _thumbDc.clear; }

    protected Wnd _wnd;                /// owner
    protected RECT* _target;           /// 更新領域を通知する対象。
    protected BmpRect _thumb;          /// ツマミのビットマップ
    protected POINT _pos;              /// ツマミ幅を含むスライダの左上の位置
    protected int _slit_length;        /// スライダの長さ
    protected int _min, _max, _value;
    /// スライダ右/下に表示されるラベル
    /// クリックでその位置にツマミが移動する。
    protected SliderStop[] _stops;

    ///
    this(Wnd wnd, RECT* tr, int min, int max,
         bool v, int x = 0, int y = 0, int len = 0)
    {
        _wnd = wnd;
        _target = tr;
        _pos = POINT(x, y);
        _slit_length = len;
        _min = min; _max = max;
        _value = min;
        _thumb = new BmpRect(tr, ready(wnd), v, x, y);
    }

    ///
    @trusted @nogc pure nothrow
    POINT getPixelPos(int p) const
    {
        static if (isV)
            return POINT(_pos.x, cast(int)(_pos.y + cast(float)_slit_length
                                           * (_max-p) / (_max - _min)));
        else
            return POINT(cast(int)(_pos.x + cast(float)_slit_length
                                   * (p-_min) / (_max - _min)), _pos.y);
    }

    ///
    @trusted @nogc pure nothrow
    int mouseToLogical(int x, int y) const
    {
        static if (isV)
            return max(_min, min(_max,
                 cast(int)(_max - cast(float)(y - _pos.y)
                           / _slit_length * (_max - _min))));
        else
            return max(_min, min(_max,
                 cast(int)(_min + cast(float)(x - _pos.x)
                           / _slit_length * (_max - _min))));
    }

    ///
    @property @trusted @nogc pure nothrow
    int value() const { return _value; }
    ///
    @property
    void value(int v)
    {
        _value = max(_min, min(_max, v));
        auto p = getPixelPos(_value);
        _thumb.set(p.x - THUMB_W/2, p.y - THUMB_H/2);
    }

    ///
    void move(int x, int y, int h)
    {
        _pos.x = x; _pos.y = y; _slit_length = h;
        value = _value;
    }

    ///
    void blitTo(Dc dc)
    {
        static if (isV)
            dc.fill!"black"(_pos.x - SLIT_W/2, _pos.y, SLIT_W, SLIT_H);
        else
            dc.fill!"black"(_pos.x, _pos.y - SLIT_H/2, SLIT_W, SLIT_H);
        foreach (one; _stops) one._text.blitTo(dc);
        _thumb.blitTo(dc);
    }

    ///
    protected POINT _offset;
    ///
    protected bool _nowDragging;

    ///
    bool mousedown(int x, int y)
    {
        if (_thumb.hits(x, y))
        {
            auto p = getPixelPos(_value);
            _offset = POINT(x - p.x, y - p.y);
            _nowDragging = true;

            foreach (one; _stops)
                one._text.setNormal;

            return true;
        }
        return false;
    }
    ///
    bool mouseup(int x, int y)
    {
        if (!_nowDragging) foreach (one; _stops)
        {
            if (one._text.hits(x, y))
            {
                value = one.value;
                return true;
            }
        }
        _nowDragging = false;
        return false;
    }

    ///
    bool mousemove(int x, int y)
    {
        if (_nowDragging)
        {
            value = mouseToLogical(x - _offset.x, y - _offset.y);
            return true;
        }
        else
        {
            foreach (one; _stops)
                one._text.mouseMove(x, y);
        }
            return false;
    }

    ///
    void clearStops()
    {
        foreach (one; _stops)
            if (one._text !is null) one._text.hide;
        _stops = null;
    }

    ///
    void resetStops(wstring[int] stops)
    {
        static if (isV)
            enum L = "E";
        else
            enum L = "S";

        auto newl = stops.length;
        for (size_t i = newl; i < _stops.length; ++i)
            _stops[i]._text.hide;
        _stops.length = newl;

        size_t i = 0;
        foreach (key, val; stops)
        {
            auto p = getPixelPos(key);
            static if (isV)
                p.x += THUMB_W/2;
            else
                p.y += THUMB_H/2;

            auto ps = &_stops[i++];
            if (ps._text is null)
                ps._text = new HoverText(_target, true);

            ps.value = key;
            ps._text.set!L(_wnd, val, p.x, p.y);
        }
    }
}

//------------------------------------------------------------------------------
alias VSlider = VHSlider!true; /// ditto
alias HSlider = VHSlider!false; /// ditto

////////////////////XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\\\\\\\\\\\\\\\\\\\\
debug(gdi):
import sworks.win32.multi_window;

final class Test
{ mixin MultiWindowMix!() MWM;

    this()
    {
        MWM.ready.regist;
        MWM.create(WS_OVERLAPPEDWINDOW | WS_VISIBLE, "test"w.ptr);
    }

    LRESULT wm_destroy(Msg)
    {
        PostQuitMessage(0);
        return 0;
    }

    void wm_paint(Dc dc, ref PAINTSTRUCT ps)
    {
        int x = 300;
        with (dc)
        {
            line!q{10 10 -- 10 100 .. 60 150 -- 160 150};
            line!q{100 20 -- 200 20 .. 200 40 -- 100 40};

            fill!"BLACK"(300, 300, 100, 100);
            fill!"GRAY"(-30, -30);

            line!q{ 200, 200 .. 100, 300 .. 200, 400 .. 300, 300 ..};

            selectBrush!"white";
            fill!q{ 200, 200 -- 100, 300 -- 200, 400 -- 300, 300 --};
            text!"NW"("hello");
        }
    }
}

void main()
{
    import std.utf : toUTF16z;
    try
    {
        scope auto mt = new Test();
        for (MSG msg; 0 < GetMessage(&msg, null, 0, 0);)
        { DispatchMessage(&msg); }
    }
    catch (WinException w) okbox(w.toStringWz);
    catch (Throwable t) okbox(t.toString.toUTF16z);
}
