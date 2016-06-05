/** ベクトル/行列演算その他
 * Version:    0.0001(dmd2.071.0)
 * Date:       2016-Jun-05 18:53:15
 * Authors:    KUMA
 * License:    CC0
*/
module sworks.base.matrix;

private import std.math;
version (unittest) import std.stdio;

enum real DOUBLE_PI = PI*2;
enum real HALF_PI = PI*0.5;
enum real TO_RADIAN = PI/180.0;
enum real TO_360 = 180.0/PI;

version (unittest)
{
    bool aEqual(T, U)(T a, U b){ return approxEqual(a, b, 1e-5, 1e-5); }
    alias Vector2!float V2;
    alias Vector3!float V3;
    alias Polar3!float P3;
    alias Quaternion!float Q4;
    alias Matrix3!float M3;
    alias Matrix4!float M4;
}

//------------------------------------------------------------------------------
/** 2 dimentional column-major Vector class. OpenGL style.
 *
 * <pre>
 *    V = | x |
 *        | y |
 * </pre>
 *
 */
struct Vector2(PRECISION)
{
    align(1)

    ///
    PRECISION[2] v = [0.0, 0.0];
    alias v this;

    @trusted @nogc pure nothrow:

    ///
    this(in PRECISION[2] s...){ v[] = s; }
    /// ditto
    this(in PRECISION s){ v[] = s; }

    ///
    @property
    ref auto x() inout { return v[0]; }
    /// ditto
    @property
    ref auto y() inout { return v[1]; }

    import std.traits : isFloatingPoint;
    static if (isFloatingPoint!PRECISION)
    {
        ///
        bool isNaN() const
        { import std.math : isNaN; return v[0].isNaN || v[1].isNaN; }
    }

    ///
    @property
    PRECISION length() const
    { return (v[0]*v[0] + v[1]*v[1]) ^^ 0.5; }
    /// ditto
    @property
    PRECISION lengthSq() const
    { return v[0]*v[0] + v[1]*v[1]; }

    ///
    ref auto normalize(in PRECISION size = 1)
    { v[] *= size / length; return this; }
    /// ditto
    Vector2 normalizedVector(in PRECISION size = 1) const
    { auto sl = size / length; return Vector2(v[0] * sl, v[1] * sl); }

    ///
    Vector2 opUnary(string OP : "-")() const
    { return Vector2(-v[0], -v[1]); }

    ///
    Vector2 opBinary(string OP)(in auto ref PRECISION[2] r) const
        if (OP == "+" || OP == "-")
    {
        return Vector2(mixin("v[0]" ~ OP ~ "r[0]")
                      , mixin("v[1]" ~ OP ~ "r[1]"));
    }
    ///
    Vector2 opBinary(string OP : "*")(in PRECISION s) const
    {
        return Vector2(mixin("v[0]" ~ OP ~ "s")
                      , mixin("v[1]" ~ OP ~ "s"));
    }

    ///
    ref auto opOpAssign(string OP)(in auto ref PRECISION[2] r)
    { mixin("v[] " ~ OP ~ "= r[];"); return this; }

    ///
    ref auto opOpAssign(string OP)(in PRECISION r)
    { mixin("v[] " ~ OP ~ "= r;"); return this; }

    ///
    ref auto opAssign(in PRECISION s)
    { v[] = s; return this; }

    ///
    ref auto rotate(in PRECISION a)
    {
        creal cs = expi(a);
        PRECISION[2] n = void;
        n[0] = (v[0]*cs.re) - (v[1]*cs.im);
        n[1] = (v[0]*cs.im) + (v[1]*cs.re);
        v[] = n;
        return this;
    }

    /// ditto
    Vector2 rotateVector(in PRECISION a) const
    {
        creal cs;
        if (__ctfe)
            cs = cos(a) + sin(a) * 1.0i;
        else
            cs = expi(a);
        Vector2 n = void;
        n[0] = (v[0]*cs.re) - (v[1]*cs.im);
        n[1] = (v[0]*cs.im) + (v[1]*cs.re);
        return n;
    }
}
/// ditto
alias Vector2!float Vector2f;

///
@trusted @nogc pure nothrow
PRECISION dot(PRECISION)(in auto ref PRECISION[2] v
                        , in auto ref PRECISION[2] r)
{ return v[0]*r[0] + v[1]*r[1]; }

///
@trusted @nogc pure nothrow
PRECISION cross(PRECISION)(in auto ref PRECISION[2] v
                          , in auto ref PRECISION[2] r)
{ return v[0]*r[1] - v[1]*r[0]; }

///
@trusted @nogc pure nothrow
PRECISION distance(PRECISION)(in auto ref PRECISION[2] v
                             , in auto ref PRECISION[2] r)
{ return (((v[0]-r[0]) ^^ 2) + ((v[1]-r[1]) ^^ 2)) ^^ 0.5; }

/// ditto
@trusted @nogc pure nothrow
PRECISION distanceSq(PRECISION)(in auto ref PRECISION[2] v
                               , in auto ref PRECISION[2] r)
{ return ((v[0]-r[0]) ^^ 2) + ((v[1]-r[1]) ^^ 2); }

unittest
{
    template _CTFE_1(V2 A, V2 B)
    {
        enum V2 _CTFE_1 = A + B;
    }

    static assert(aEqual(_CTFE_1!(V2(1, 2), V2(2, 3))[], V2(3, 5)[]));
}

/// 線形補完
@trusted @nogc pure nothrow
Vector2!PRECISION interpolateLinear(PRECISION)
    (in auto ref Vector2!PRECISION a, in PRECISION r
    , in auto ref Vector2!PRECISION b)
{ return ((b-a) * r) + a; }

unittest
{
    V2 a = V2(1, 2);
    assert(aEqual(a.length, 2.2360679));
    assert(aEqual(a.lengthSq, 5));
    auto b = a.normalizedVector;
    assert(aEqual(a.cross(b), 0));
    assert(aEqual(a.dot(b), a.length));
    a = V2(1, 0);
    a.rotate(HALF_PI);
    assert(aEqual(a[], V2(0, 1)[]));
    a = V2(0, 0);
    b = V2(2, 0);
    assert(aEqual(interpolateLinear(a, 0.5f, b)[], V2(1, 0)[]));
    a = V2(float.nan, float.nan);
    assert(a.isNaN);
}

//------------------------------------------------------------------------------
/// 2次ベジェ曲線
struct QuadraticBezier(PRECISION)
{
    private Vector2!PRECISION p1, v1, v2;

    @trusted @nogc pure nothrow:
    /**
     * Parmas:
     *   _1 = 始点
     *   c1 = 制御点
     *   p2 = 終点
    **/
    this(in PRECISION[2] _1, in PRECISION[2] c1, in PRECISION[2] p2)
    {
        p1 = _1;
        v1 = Vector2!PRECISION(c1) - Vector2!PRECISION(p1);
        v2 = Vector2!PRECISION(p2) - Vector2!PRECISION(c1);
    }

    /** 曲線上の点を返す。
     * Params:
     * t = [0, 1] で、0のとき始点、1の時終点となる。
    **/
    Vector2!PRECISION opCall(in PRECISION t) const
    {
        auto a = v1 * t;
        auto b = v1 + v2 * t;
        return  p1 + a + (b - a) * t;
    }

    /// $(LINK http://stackoverflow.com/questions/11854907/calculate-the-length-of-a-segment-of-a-quadratic-bezier)
    PRECISION calcLength() const
    {
        import std.math : sqrt, log, abs;
        auto p2 = v2 + v1;
        auto _a = Vector2!PRECISION(0, 0) - v1 * 2 + p2;
        auto _b = v1 * 2;

        auto A = 4 * _a.lengthSq;
        auto B = _a.dot(_b);
        auto C = _b.lengthSq;

        auto b = B / (2 * A);
        auto c = C / A;
        auto u = 1 + b;
        auto k = c - b * b;

        auto u_ = sqrt(u*u+k);
        auto b_ = sqrt(b*b+k);
        return (sqrt(A) / 2) * (u * u_ - b * b_ + log(abs((u+u_)/(b+b_))));
    }
}

/// 3次ベジェ曲線
struct CubicBezier(PRECISION)
{
    private Vector2!PRECISION p1, c1, c2, v1, v2, v3;

    @trusted @nogc pure nothrow:

    /**
     * Params:
     *   _1 = 始点
     *   _2 = 制御点1
     *   _3 = 制御点2
     *   p2 = 終点
    **/
    this(in PRECISION[2] _1, in PRECISION[2] _2
        , in PRECISION[2] _3, in PRECISION[2] p2)
    {
        p1 = _1; c1 = _2; c2 = _3;
        v1 = c1 - p1;
        v2 = Vector2!PRECISION(p2) - c2;
        v3 = c2 - c1;
    }

    /// t = [0..1]
    Vector2!PRECISION opCall(in PRECISION t) const
    {
        auto a = p1 + v1 * t;
        auto b = c2 + v2 * t;
        auto c = c1 + v3 * t;
        auto d = a + (c - a) * t;
        auto e = c + (b - c) * t;
        return d + (e - d) * t;
    }


    /// $(LINK http://www.gamedev.net/topic/313018-calculating-the-length-of-a-bezier-curve/)
    PRECISION calcLength() const
    {
        PRECISION bezLength(in ref Vector2!PRECISION[4] b)
        {
            import std.math : abs;
            auto p0 = (b[0] - b[1]);
            auto p1 = (b[2] - b[1]);
            Vector2!PRECISION p2;
            auto p3 = (b[3] - b[2]);
            auto l0 = p0.length;
            auto l1 = p1.length;
            auto l3 = p3.length();
            if (l0 > 0f) p0 /= l0;
            if (l1 > 0f) p1 /= l1;
            if (l3 > 0f) p3 /= l3;
            p2 = -p1;
            auto a = abs(p0.dot(p1)) + abs(p2.dot(p3));
            if ((a > 1.98f) || ((l0+l1+l3) < ((4f - a)*8f)))
                return l0+l1+l3;

            Vector2!PRECISION[4] bl, br;
            bl[0] = b[0];
            bl[1] = (b[0]+b[1])*.5f;
            auto mid = (b[1]+b[2])*.5f;
            bl[2] = (bl[1]+mid)*.5f;
            br[3] = b[3];
            br[2] = (b[2]+b[3])*.5f;
            br[1] = (br[2]+mid)*.5f;
            br[0] = (br[1]+bl[2])*.5f;
            bl[3] = br[0];
            return bezLength(bl) + bezLength(br);
        } // bezLength
        Vector2!PRECISION[4] b;
        b[0] = p1; b[1] = c1; b[2] = c2; b[3] = v2 + c2;
        return bezLength(b);
    }
}

/** 弧
 *
 * SVGのパスを構成する A コマンドの実装。$(BR)
 * $(LINK http://www.w3.org/TR/SVG/implnote.html#ArcImplementationNotes)
**/
struct Arc(PRECISION)
{
    private Vector2!PRECISION c, r;
    private Matrix2!PRECISION x;
    private PRECISION startA, deltaA;

    @trusted @nogc pure nothrow:

    /**
     * 角度の単位はラジアンで、X軸から反時計回りを正とする。
     * Params:
     *   _c = 中心座標
     *   r  = 楕円それぞれの半径
     *   xa = ローカル座標系が、ワールド座標に対してどれだけ傾いているか。
     *   sa = 開始角。
     *   da = 終了角。
    **/
    this(in PRECISION[2] _c, in PRECISION[2] r, in PRECISION xa
        , in PRECISION sa, in PRECISION da)
    {
        import std.math : expi;

        c = _c;
        creal cs;
        if (__ctfe) cs = cos(xa) + sin(xa) * 1.0i;
        else cs = expi(xa);
        this.r = r;
        x = rotateMatrix2!PRECISION(xa);
        startA = sa; deltaA = da;
    }

    /**
     * Params:
     *   _p1 = 始点
     *   _p2 = 終点
     *   _r  = 半径
     *   xa  = ローカル座標系が、ワールド座標に対してどれだけ傾いているか。
     *   lf  = 大きい方の弧である場合は true。
     *   sf  = 反時計回りである場合は true。
     *
     * Bugs:
     *   CTFE 時に精度が落ちる。
    **/
    this(in PRECISION[2] _p1, in PRECISION[2] _p2, in PRECISION[2] _r
        , in PRECISION xa, in bool lf, in bool sf)
    {
        import std.math : sqrt;

        auto p1 = Vector2!PRECISION(_p1);
        auto p2 = Vector2!PRECISION(_p2);
        auto r = Vector2!PRECISION(_r);

        auto a = ((p1 - p2) * 0.5).rotateVector(-xa);

        auto x2 = a.x * a.x;
        auto y2 = a.y * a.y;
        auto rx2 = r.x * r.x;
        auto ry2 = r.y * r.y;
        auto t = (lf == sf ? -1 : 1)
               * sqrt((rx2 * ry2 - rx2 * y2 - ry2 * x2)
                     / (rx2 * y2 + ry2 * x2));
        auto b = Vector2!PRECISION(r.x * a.y / r.y, - r.y * a.x / r.x) * t;


        auto _c = b.rotateVector(xa) + ((p1 + p2) * 0.5);

        auto u1 = Vector2!PRECISION(1, 0);
        auto v1 = Vector2!PRECISION((a.x - b.x)/r.x, (a.y - b.y)/r.y);

//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// Bug: CTFE 時に、cross1≒0で cross の符号が逆になってしまう。
        auto cross1 = u1.cross(v1);
        auto sa = ((!__ctfe || !approxEqual(cross1, 0)) && cross1 < 0 ? -1 : 1)
                * ct_acos(u1.dot(v1) / (u1.length * v1.length));
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

        auto u2 = v1;
        auto v2 = Vector2!PRECISION((-a.x - b.x)/r.x, (-a.y - b.y)/r.y);
        auto da = ((u2.cross(v2) < 0 ? -1 : 1)
                * ct_acos(u2.dot(v2) / (u2.length * v2.length))) % DOUBLE_PI;
        if (sf == (da < 0)) da *= -1;
        this(_c, r, xa, sa, da);
    }

    ///
    Vector2!PRECISION opCall(in PRECISION t) const
    {
        import std.math : expi;
        auto a = startA + deltaA * t;
        creal cs;
        if (__ctfe) cs = cos(a) + sin(a) * 1.0i;
        else cs = expi(a);
        auto tr = Vector2!PRECISION(r.x * cs.re, r.y * cs.im);
        return x * tr + c;
    }
}

unittest
{
    enum float[2] ppos = [282.33762,290.70717];
    enum float[2] r = [101.52033,85.357887];
    enum float f = 0;
    enum bool flag_1 = 0;
    enum bool flag_2 = 1;
    enum float[2] pos1 = [383.85795,205.34929];
    enum arc = Arc!float(ppos, pos1, r, f, flag_1, flag_2);
    auto arc2 = Arc!float(ppos, pos1, r, f, flag_1, flag_2);

    auto func()
    {
        auto buf = new V2[100];
        for (size_t i = 0; i < 100; ++i)
            buf[i] = arc((cast(float)i)/100f);
        return buf;
    }

    enum on_ctfe = func();
    auto on_runtime = func();

    for (size_t i = 0; i < 100; ++i)
    {
        assert(aEqual(on_ctfe[i].v[0], on_runtime[i].v[0]));
        assert(aEqual(on_ctfe[i].v[1], on_runtime[i].v[1]));
    }
}


/// acos が CTFE できないのでかわり。
@trusted @nogc pure nothrow
float ct_acos(float x)
{
    import std.math : acos, sqrt;
    if (__ctfe) return ct_atan2(sqrt(1-x*x), x);
    else return std.math.acos(x);
}

//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
/// y、xの値が0付近で精度落ちます。
@trusted @nogc pure nothrow
float ct_atan2(float y, float x)
{
    import std.math : isNaN, isInfinity, PI, PI_2, PI_4;
    if (__ctfe)
    {
    // Special cases.
    if (isNaN(x) || isNaN(y))
        return real.nan;
    if (approxEqual(y, 0))
    {
        if (x >= 0 && !ct_signbit(x))
            return ct_copysign(0, y);
        else
            return ct_copysign(PI, y);
    }
    if (approxEqual(x, 0))
        return ct_copysign(PI_2, y);
    if (isInfinity(x))
    {
        if (ct_signbit(x))
        {
            if (isInfinity(y))
                return ct_copysign(3*PI_4, y);
            else
                return ct_copysign(PI, y);
        }
        else
        {
            if (isInfinity(y))
                return ct_copysign(PI_4, y);
            else
                return ct_copysign(0.0, y);
        }
    }
    if (isInfinity(y))
        return ct_copysign(PI_2, y);

    // Call atan and determine the quadrant.
    real z = ct_atan(y / x);

    if (ct_signbit(x))
    {
        if (ct_signbit(y))
            z = z - PI;
        else
            z = z + PI;
    }

    if (z == 0.0)
        return ct_copysign(z, y);

        return z;
    }
    else return std.math.atan2(x, y);
}

///
@trusted @nogc pure nothrow
float ct_atan(float x)
{
    import std.math : isInfinity, PI_2, PI_4, poly;
    if (__ctfe)
    {
        // Coefficients for atan(x)
        static immutable real[5] P = [
           -5.0894116899623603312185E1L,
           -9.9988763777265819915721E1L,
           -6.3976888655834347413154E1L,
           -1.4683508633175792446076E1L,
           -8.6863818178092187535440E-1L,
];
        static immutable real[6] Q = [
            1.5268235069887081006606E2L,
            3.9157570175111990631099E2L,
            3.6144079386152023162701E2L,
            1.4399096122250781605352E2L,
            2.2981886733594175366172E1L,
            1.0000000000000000000000E0L,
];

        // tan(PI/8)
        enum real TAN_PI_8 = 4.1421356237309504880169e-1L;
        // tan(3 * PI/8)
        enum real TAN3_PI_8 = 2.41421356237309504880169L;

        // Special cases.
        if (x == 0.0)
            return x;
        if (isInfinity(x))
            return ct_copysign(PI_2, x);

        // Make argument positive but save the sign.
        bool sign = false;
        if (ct_signbit(x))
        {
            sign = true;
            x = -x;
        }

        // Range reduction.
        real y;
        if (x > TAN3_PI_8)
        {
            y = PI_2;
            x = -(1.0 / x);
        }
        else if (x > TAN_PI_8)
        {
            y = PI_4;
            x = (x - 1.0)/(x + 1.0);
        }
        else
            y = 0.0;

        // Rational form in x^^2.
        real z = x * x;
        y = y + (poly(z, P) / poly(z, Q)) * z * x + x;

        return (sign) ? -y : y;
    }
    else return std.math.atan(x);
}

///
@trusted @nogc pure nothrow
int ct_signbit(float x)
{
    if (__ctfe) return (x < 0) ? 1 : 0;
    else return std.math.signbit(x);
}

///
@trusted @nogc pure nothrow
float ct_copysign(float to, float from)
{
    import std.math : copysign;
    if (__ctfe)
    {
        if ((to * from) < 0) return to * -1;
        else return to;
    }
    else return std.math.copysign(to, from);
}

unittest
{
    enum rad = -0.99999999f;
    enum ac_on_ct = ct_acos(rad);
    auto ac_on_rt = acos(rad);

    import std.math : approxEqual;
    // ↓精度落ちてます。
    assert(approxEqual(ac_on_ct, ac_on_rt, 1e-2, 1e-4));
}


///
struct Ellipse(PRECISION)
{
    Vector2!PRECISION center, size;

    @trusted @nogc pure nothrow:

    ///
    this(in PRECISION[2] c, in PRECISION[2] s)
    {
        center = Vector2!PRECISION(c);
        size = Vector2!PRECISION(s);
    }

    ///
    Vector2!PRECISION opCall(in PRECISION t) const
    {
        auto r = DOUBLE_PI * t;
        creal cs;
        if (__ctfe) cs = cos(r) + sin(r) * 1.0i;
        else cs = expi(r);
        return Vector2!PRECISION(size.x * cs.re, size.y * cs.im) + center;
    }
}


//------------------------------------------------------------------------------
/** 3 dimentional column-major Vector class. OpenGL style.
 *
 * <pre>
 *        | x |
 *    V = | y |
 *        | z |
 * </pre>
 *
 */
align(1)
struct Vector3(PRECISION)
{
    align(1):
    ///
    PRECISION[3] v = [0.0, 0.0, 0.0];
    alias v this;

    @trusted @nogc pure nothrow:

    /// constructor
    this(PRECISION s) { v[] = s; }
    /// ditto
    this(in PRECISION[3] s ...) { v[] = s; }
    /// ditto
    this(in ref PRECISION[3] s){ v[] = s; }

    ///
    @property
    ref auto x() inout { return v[0]; }
    /// ditto
    @property
    ref auto y() inout { return v[1]; }
    /// ditto
    @property
    ref auto z() inout { return v[2]; }

    // properties
    ///
    @property
    PRECISION length() const
    { return (v[0]*v[0]+v[1]*v[1]+v[2]*v[2]) ^^ 0.5; }
    /// ditto
    @property
    PRECISION lengthSq() const
    { return v[0]*v[0] + v[1]*v[1] + v[2]*v[2]; }

    ///
    ref Vector3 normalize(PRECISION size = 1)
    { v[] *= size / length; return this; }
    /// ditto
    Vector3 normalizedVector(PRECISION size = 1) const
    {
        PRECISION[3] n = v;
        n[] *= size / length;
        return Vector3(n);
    }

    // operator overloading
    ///
    Vector3 opUnary(string OP : "-")() const
    {
        PRECISION[3] n = v;
        n[] *= -1;
        return Vector3(n);
    }

    ///
    Vector3 opBinary(string OP)(in auto ref PRECISION[3] s) const
    {
        PRECISION[3] n = v;
        mixin("n[] " ~ OP~"= s[];");
        return Vector3(n);
    }

    ///
    Vector3 opBinary(string OP)(PRECISION s) const
    {
        PRECISION[3] n = v;
        mixin("n[] " ~ OP ~ "= s;");
        return Vector3(n);
    }

    ///
    ref Vector3 opOpAssign(string OP)(in auto ref PRECISION[3] s)
    { mixin("v[] " ~ OP ~ "= s[];"); return this; }

    ///
    ref Vector3 opOpAssign(string OP)(in PRECISION s)
    { mixin("v[] " ~ OP ~ "= s;"); return this; }


    ///
    ref Vector3 opAssign(PRECISION s)
    { v[] = s;  return this;}
    /// ditto
    ref Vector3 opAssign(in PRECISION[3] s ...)
    { v[] = s[]; return this; }
    /// ditto
    ref Vector3 opAssign(in ref PRECISION[3] s)
    { v[] = s[]; return this; }

    ///
    ref Vector3 rotate()(in PRECISION a, in auto ref PRECISION[3] r)
    {
        creal cs = expi(a);
        PRECISION c = cs.re;
        PRECISION s = cs.im;
        PRECISION c1 = 1-c;
        PRECISION[3] n = void;
        n[0] = v[0] * ((r[0]*r[0]*c1)+c)
             + v[1] * ((r[0]*r[1]*c1)-(r[2]*s))
             + v[2] * ((r[0]*r[2]*c1)+(r[1]*s));

        n[1] = v[0] * ((r[1]*r[0]*c1)+(r[2]*s))
             + v[1] * ((r[1]*r[1]*c1)+c)
             + v[2] * ((r[1]*r[2]*c1)-(r[0]*s));

        n[2] = v[0] * ((r[0]*r[2]*c1)-(r[1]*s))
             + v[1] * ((r[1]*r[2]*c1)+(r[0]*s))
             + v[2] * ((r[2]*r[2]*c1)+c);
        v[] = n[];
        return this;
    }

    /// ditto
    ref Vector3 rotateYZ(in PRECISION a)
    {
        creal cs = expi(a); // con(a)==cs.re; sin(a)==cs.im;
        PRECISION[3] n = void;
        n[0] = v[0];
        n[1] = (v[1]*cs.re) - (v[2]*cs.im);
        n[2] = (v[1]*cs.im) + (v[2]*cs.re);
        v[] = n[];
        return this;
    }
    /// ditto
    ref Vector3 rotateZX(in PRECISION a)
    {
        creal cs = expi(a); // con(a)==cs.re; sin(a)==cs.im;
        PRECISION[3] n = void;
        n[0] = (v[0]*cs.re) + (v[2]*cs.im);
        n[1] = v[1];
        n[2] = -(v[0]*cs.im) + (v[2]*cs.re);
        v[] = n[];
        return this;
    }
    /// ditto
    ref Vector3 rotateXY(in PRECISION a)
    {
        creal cs = expi(a); // con(a)==cs.re; sin(a)==cs.im;
        PRECISION[3] n = void;
        n[0] = (v[0]*cs.re) - (v[1]*cs.im);
        n[1] = (v[0]*cs.im) + (v[1]*cs.re);
        n[2] = v[2];
        v[] = n[];
        return this;
    }
}
/// ditto
alias Vector3!double Vector3d;
/// ditto
alias Vector3!float Vector3f;

unittest
{
    template _CTFE(V3 A, V3 B) { enum V3 _CTFE = A + B; }
    static assert(aEqual(_CTFE!(V3(1,2,3), V3(4,5,6))[], V3(5,7,9)[]));
}

unittest
{
    V3 v = V3(3, 4, 5);
    assert(-v == [-3, -4, -5]);
    assert(aEqual(v.length, (-v).length));
    assert(50 == v.lengthSq);
    assert(aEqual(7.0711, v.length));
    auto v2 = v.normalizedVector;
    assert(aEqual(1.0000, v2.length));
    v.normalize;
    assert(aEqual(1.0000, v.length));

    v = [3, 4, 5];
    v2 = [1, 2, 3];
    assert(v + v2 == [4, 6, 8]);
    assert(v - v2 == [2, 2, 2]);
    assert(v * 2 == [6, 8, 10]);
    assert((v += v2) == [4, 6, 8]);
    assert((v2 -= v) == [-3, -4, -5]);
    assert((v *= 2) == [8, 12, 16]);
    assert((v = 0) == [0, 0, 0]);
    assert((v = v2) == v2);
    assert(aEqual(v.rotate(2 * PI, [1, 0, 0])[], v2[]));

    assert(aEqual(v.rotateYZ(1).length, v2.length));
    assert(aEqual(v.rotateZX(1).length, v2.length));
    assert(aEqual(v.rotateXY(1).length, v2.length));
}

///
@trusted @nogc pure nothrow
PRECISION dot(PRECISION)(in auto ref PRECISION[3] v1
                        , in auto ref PRECISION[3] v2)
{
    PRECISION[3] n = v1;
    n[] *= v2[];
    return n[0] + n[1] + n[2];
}
unittest
{
    V3 a = V3(3, 4, 0);
    V3 b = a;
    b.rotateXY(HALF_PI);
    assert(aEqual(a.dot(b), 0));
}


///
@trusted @nogc pure nothrow
Vector3!PRECISION cross(PRECISION)(in auto ref PRECISION[3] v1
                                  , in auto ref PRECISION[3] v2)
{
    return Vector3!PRECISION(v1[1]*v2[2]-v1[2]*v2[1]
                            , v1[2]*v2[0]-v1[0]*v2[2]
                            , v1[0]*v2[1]-v1[1]*v2[0]);
}
unittest
{
    V3 a = V3(1, 2, 3);
    V3 b = V3(3, 4, 5);
    V3 c = a.cross(b);
    assert(aEqual(a.dot(c), 0));
}

///
@trusted @nogc pure nothrow
PRECISION distance(PRECISION)(in auto ref PRECISION[3] v1
                             , in auto ref PRECISION[3] v2)
{
    PRECISION[3] n = v1;
    n[] -= v2[];
    return (n[0] * n[0] + n[1] * n[1] + n[2] * n[2]) ^^ 0.5;
}
/// ditto
@trusted @nogc pure nothrow
PRECISION distanceSq(PRECISION)(in auto ref PRECISION[3] v1
                             , in auto ref PRECISION[3] v2)
{
    PRECISION[3] n = v1;
    n[] -= v2[];
    return n[0] * n[0] + n[1] * n[1] + n[2] * n[2];
}
unittest
{
    V3 a = V3(1, 2, 3);
    V3 b = V3(4, 5, 6);
    V3 c = a - b;
    assert(aEqual(c.length, a.distance(b)));
    assert(aEqual(c.lengthSq, a.distanceSq(b)));
}


///
@trusted @nogc pure nothrow
PRECISION length(PRECISION)(in PRECISION x, in PRECISION y, in PRECISION z)
{ return (x*x + y*y + z*z) ^^ 0.5; }

/// ditto
@trusted @nogc pure nothrow
PRECISION lengthSq(PRECISION)(in PRECISION x, in PRECISION y, in PRECISION z)
{ return x*x + y*y + z*z; }

unittest
{
    assert(aEqual(length(3.0, 4.0, 5.0), 7.071));
    assert(aEqual(lengthSq(3.0, 4.0, 5.0), 50.0));
}

///
@trusted @nogc pure nothrow
Vector3!PRECISION normalizedVector(PRECISION)(in PRECISION x, in PRECISION y
                                             , in PRECISION z
                                             , in PRECISION size = 1)
{
    PRECISION sl = size / ((x*x + y*y + z*z) ^^ 0.5);
    return Vector3!PRECISION(x * sl, y * sl, z * sl);
}
unittest
{
    assert(aEqual(normalizedVector(3.0, 4.0, 5.0)[]
                  , [0.42426, 0.56569, 0.70711]));
}

/// 線形補完
@trusted @nogc pure nothrow
Vector3!PRECISION interpolateLinear(PRECISION)
    (in auto ref Vector3!PRECISION a, in PRECISION r
    , in auto ref Vector3!PRECISION b)
{ return ((b-a) * r) + a; }

unittest
{
    auto a = V3(0, 0, 0);
    auto b = V3(1, 2, 3);
    assert(aEqual(interpolateLinear(a, 0.5f, b)[], (b * 0.5)[]));
}

//------------------------------------------------------------------------------
// Polar3
/// 3 component polar class
struct Polar3(PRECISION)
{
    PRECISION longitude = 0; /// East <-> West
    PRECISION latitude = 0;  /// South <-> North
    PRECISION radius = 1;    ///

    @trusted @nogc pure nothrow

    ///
    this(in PRECISION lg, in PRECISION lt, in PRECISION r)
    { longitude = lg; latitude = lt; radius = r; }

    ///
    ref Polar3 normalize()
    {
        latitude %= DOUBLE_PI;
        if (latitude < 0) latitude += DOUBLE_PI;

        if (HALF_PI < latitude && latitude < PI+HALF_PI)
        {
            longitude += PI;
            latitude = PI - latitude;
        }
        else if (PI+HALF_PI <= latitude) latitude -= DOUBLE_PI;

        if (longitude < -PI) longitude = DOUBLE_PI + (longitude % DOUBLE_PI);
        longitude = ((longitude + PI) % DOUBLE_PI) - PI;
        return this;
    }
}
/// ditto
alias Polar3!double Polar3d;
/// ditto
alias Polar3!float Polar3f;

unittest
{
    alias Polar3!float P3;
    P3 p3 = P3(DOUBLE_PI + 2.5, DOUBLE_PI * 4 + 1, 3);
    p3.normalize;
    assert(aEqual(p3.longitude, 2.5));
    assert(aEqual(p3.latitude, 1));
}

///
@trusted @nogc pure nothrow
Polar3!(PRECISION) toPolar(PRECISION)(in auto ref PRECISION[3] v)
{
    Polar3!PRECISION p;
    p.radius = (v[0]*v[0] + v[1]*v[1] + v[2]*v[2]) ^^ 0.5;
    if (0 < p.radius)
    {
        p.latitude = asin(v[1] / p.radius);
        if (0 == v[2])
        {
            if (0 < v[0]) p.longitude = 0;
            else p.longitude = HALF_PI;
        }
        else
        {
            p.longitude = atan2 (-v[2] , v[0]);
        }
    }
    return p;
}

///
@trusted @nogc pure nothrow
Vector3!(PRECISION) toVector(PRECISION)(in auto ref Polar3!PRECISION p)
{
    Vector3!PRECISION v;
    creal lati_sc = expi(p.latitude);
    creal long_sc = expi(p.longitude);
    v.y = p.radius * lati_sc.im;
    v.z = -p.radius * lati_sc.re * long_sc.im;
    v.x = p.radius * lati_sc.re * long_sc.re;
    return v;
}
unittest
{
    V3 a = V3(3, 4, 5);
    P3 p = a.toPolar;
    assert(aEqual(a[], p.toVector[]));
}


//------------------------------------------------------------------------------
/// Quaternion
struct Quaternion(PRECISION)
{
    ///
    PRECISION[4] v = [1, 0, 0, 0];
    alias v this;

    @trusted @nogc pure nothrow:

    ///
    this(in PRECISION[3] s ...) { v[1..4] = s[]; v[0] = 1; }
    /// ditto
    this(in ref PRECISION[3] s) { v[1..4] = s[]; v[0] = 1; }
    ///
    this(in PRECISION[4] s ...) { v[] = s[]; }
    /// ditto
    this(in ref PRECISION[4] s) { v[] = s; }

    ///
    @property
    ref auto w() inout { return v[0]; }
    /// ditto
    @property
    ref auto x() inout { return v[1]; }
    /// ditto
    @property
    ref auto y() inout { return v[2]; }
    /// ditto
    @property
    ref auto z() inout { return v[3]; }

    ///
    @property
    PRECISION length() const
    { return (v[0]*v[0] + v[1]*v[1] + v[2]*v[2] + v[3]*v[3]) ^^ 0.5; }
    /// ditto
    @property
    PRECISION lengthSq() const
    { return v[0]*v[0] + v[1]*v[1] + v[2]*v[2] + v[3]*v[3]; }

    ///
    ref Quaternion normalize()
    { v[] /= length; return this; }

    /// ditto
    Quaternion normalizedQuaternion() const
    {
        PRECISION[4] n = v;
        n[] /= length;
        return Quaternion(n);
    }

    ///
    Quaternion opBinary(string OP)(in auto ref PRECISION[4] q) const
        if (OP == "+" || OP == "-")
    {
        PRECISION[4] n = v;
        mixin("n[] " ~ OP ~ "= q[];");
        return Quaternion(n);
    }
    ///
    ref Quaternion opOpAssign(string OP)(in auto ref PRECISION[4] q)
        if (OP == "+" || OP == "-")
    { mixin("v[] " ~ OP ~ "= q[];"); return this; }


    private void _mul(in ref PRECISION[4] q, out PRECISION[4] o) const
    {
        o[0] = v[0]*q[0] - v[1]*q[1] - v[2]*q[2] - v[3]*q[3];
        o[1] = v[0]*q[1] + v[1]*q[0] + v[2]*q[3] - v[3]*q[2];
        o[2] = v[0]*q[2] - v[1]*q[3] + v[2]*q[0] + v[3]*q[1];
        o[3] = v[0]*q[3] + v[1]*q[2] - v[2]*q[1] + v[3]*q[0];
    }

    ///
    Vector3!PRECISION opBinary(string OP : "*")(in auto ref PRECISION[3] v)const
    {
        auto qv = Quaternion(v);
        auto conj = conjugate;
        auto aqv = this * qv * conj;
        return Vector3!PRECISION(aqv[1..4]);
    }

    ///
    Quaternion opBinary(string OP : "*")(in auto ref PRECISION[4] q) const
    {
        Quaternion n = void;
        _mul(q, n.v);
        return n;
    }
    ///
    ref Quaternion opOpAssign(string OP : "*")(in auto ref PRECISION[4] q)
    {
        PRECISION[4] n = void;
        _mul(q, n);
        v[] = n;
        return this;
    }

    ///
    Quaternion opBinary(string OP)(in PRECISION a) const
    {
        PRECISION[4] n = v;
        mixin("n[] " ~ OP ~ "= a;");
        return Quaternion(n);
    }

    ///
    ref Quaternion opOpAssign(string OP)(in PRECISION a)
    { mixin("v[] " ~ OP ~ "=a;"); return this; }

    ///
    @property
    Quaternion conjugate() const
    {
        auto n = Quaternion(v);
        n[1..4] *= -1;
        return n;
    }

    private static void _rot()(in PRECISION rad, in ref PRECISION[3] axis
                            , out PRECISION[4] o)
    {
        creal cs = expi(rad * 0.5);
        o[0] = cs.re;
        o[1] = cs.im * axis[0];
        o[2] = cs.im * axis[1];
        o[3] = cs.im * axis[2];
    }

    ///
    ref Quaternion rotate()(in PRECISION rad, in auto ref PRECISION[3] axis)
    {
        Quaternion q = void;
        _rot(rad, axis, q);
        PRECISION[4] n = void;
        q._mul(v, n);
        v[] = n;
        return this;
    }

    /// ditto
    static Quaternion rotateQuaternion()(in PRECISION rad
                                        , in auto ref PRECISION[3] axis)
    {
        Quaternion n = void;
        _rot(rad, axis, n.v);
        return n;
    }
}
/// ditto
alias Quaternion!float Quaternionf;

unittest
{
    V3 a = V3(1, 0, 0);
    Q4 q = rotateQuaternionf(HALF_PI, [0, 0, 1]);
    a = q * a;
    assert(aEqual(a[], [0.0f, 1.0f, 0.0f]));

    a = V3(1, 0, 0);
    q = rotateQuaternionf(HALF_PI, [0, 0, 1]);
    Q4 q2 = rotateQuaternionf(HALF_PI, [1, 0, 0]);
    q = q2 * q;
    a = q * a;
    assert(aEqual(a[], [0.0f, 0.0f, 1.0f]));


    a = V3(3, 4, 5);
    V3 b = a;
    V3 c = V3(1.0f, 2.0f, 3.0f);
    V3 d = a.cross(c).normalizedVector;
    q = rotateQuaternionf(HALF_PI, d);

    a = q * a;
    assert(aEqual(a.dot(b), 0.0f));

    a = b;
    q = rotateQuaternionf(HALF_PI, d);
    a = q * a;
    a = q * a;
    a = q * a;
    a = q * a;
    assert(aEqual(a[], b[]));

}

/// suger
template rotateQuaternion(PRECISION)
{ alias rotateQuaternion = Quaternion!PRECISION.rotateQuaternion; }
/// ditto
alias rotateQuaternionf = rotateQuaternion!float;

///
@trusted @nogc pure nothrow
PRECISION dot(PRECISION)(in auto ref PRECISION[4] a
                        , in auto ref PRECISION[4] b)
{
    PRECISION[4] n = a;
    n[] *= b[];
    return n[0] + n[1] + n[2] + n[3];
}

///
@trusted @nogc pure nothrow
Quaternion!PRECISION interpolateLinear(PRECISION)
    (in ref Quaternion!PRECISION a, in PRECISION t)
{
    PRECISION sSq = 1.0 - a.w * a.w;
    PRECISION s;
    if (sSq <= 0.0 || (s = sqrt(sSq)) == 0.0) return a;

    PRECISION delta = acos(a.w);
    PRECISION s1 = 1 / s;
    auto a2 = a * (sin((1 - t) * delta) * s1);
    a2.w += (sin(t * delta) * s1);
    return a2;
}

/// s → q への回転角が最短になるように q の符号を反転する。
ref auto selectMinimumRotation(PRECISION)
    (ref Quaternion!PRECISION q, in auto ref Quaternion!PRECISION s)
{ if ((s+q).lengthSq < (s-q).lengthSq) q *= -1; return q; }

/**
 * Params:
 *   a, b = normalized quaternion.
 *   t    = [0 .. 1]
 */
@trusted @nogc pure nothrow
Quaternion!PRECISION interpolateLinear(PRECISION)
    (in auto ref Quaternion!PRECISION a, in PRECISION t
    , in auto ref Quaternion!PRECISION b)
{
    PRECISION adotb = dot(a, b);
    PRECISION sSq = 1.0 - adotb * adotb;
    PRECISION s;
    if (sSq <= 0.0 || (s = sqrt(sSq)) == 0.0) return a;

    PRECISION delta = acos(adotb);
    PRECISION s1 = 1 / s;
    auto a2 = a * (sin((1 - t) * delta) * s1);
    auto b2 = b * (sin(t * delta) * s1);
    return a2 + b2;
}
unittest
{
    V3 a = V3(3, 4, 5);
    V3 b = normalizedVector(6.0f, 8.0f, -2.0f);
    Q4 q1;
    Q4 q2 = rotateQuaternionf(PI, b);
    Q4 q3 = rotateQuaternionf(HALF_PI, b);
    Q4 q4 = interpolateLinear(q1, 0.5f, q2);
    assert(aEqual(q3[], q4[]));
}

///
@trusted @nogc pure nothrow
Matrix4!PRECISION toMatrix(PRECISION)(in auto ref PRECISION[4] q)
{
    return Matrix4!PRECISION(
          1 - 2*q[2]*q[2] - 2*q[3]*q[3]
        , 2*q[1]*q[2] + 2*q[0]*q[3]
        , 2*q[1]*q[3] - 2*q[0]*q[2]
        , 0

        , 2*q[1]*q[2] - 2*q[0]*q[3]
        , 1 - 2*q[1]*q[1] - 2*q[3]*q[3]
        , 2*q[2]*q[3] + 2*q[0]*q[1]
        , 0

        , 2*q[1]*q[3] + 2*q[0]*q[2]
        , 2*q[2]*q[3] - 2*q[0]*q[1]
        , 1 - 2*q[1]*q[1] - 2*q[2]*q[2]
        , 0

        , 0, 0, 0, 1);
}

unittest
{
    auto q1 = rotateQuaternionf(HALF_PI * 0.5
                                , normalizedVector(3.0f, 4.0f, 5.0f));
    auto v1 = V3(1, 2, 3);
    auto v2 = q1 * v1;
    auto m1 = q1.toMatrix;
    auto v3 = m1 * v1;
    assert(aEqual(v2[], v3[]));
}

///
// from $(LINK www.euclideanspace.com/maths/geometry/rotations/conversions/matrixToQuaternion/)
@trusted @nogc pure nothrow
Quaternion!PRECISION toQuaternion(PRECISION)(in auto ref Matrix4!PRECISION m)
{
    PRECISION tr = m[0] + m[5] + m[10];
    Quaternion!PRECISION q = void;

    if      (0 < tr)
    {
        PRECISION s = sqrt(tr+1) * 2;                 // s = 4 * qw
        q[0] = 0.25 * s;
        q[1] = (m[6] - m[9]) / s;
        q[2] = (m[8] - m[2]) / s;
        q[3] = (m[1] - m[4]) / s;
    }
    else if ((m[5] < m[0]) && (m[10] < m[0]))
    {
        PRECISION s = sqrt(1 + m[0] - m[5] - m[10]) * 2; // s = 4 * qx;
        q[0] = (m[6] - m[9]) / s;
        q[1] = 0.25 * s;
        q[2] = (m[4] + m[1]) / s;
        q[3] = (m[8] + m[2]) / s;
    }
    else if (m[10] < m[5])
    {
        PRECISION s = sqrt(1 + m[5] - m[0] - m[10]) * 2; // s = 4 * qy
        q[0] = (m[8] - m[2]) / s;
        q[1] = (m[4] + m[1]) / s;
        q[2] = 0.25 * s;
        q[3] = (m[9] + m[6]) / s;
    }
    else
    {
        PRECISION s = sqrt(1 + m[10] - m[0] - m[5]) * 2; // s = 4 * qz
        q[0] = (m[1] - m[4]) / s;
        q[1] = (m[8] + m[2]) / s;
        q[2] = (m[9] + m[6]) / s;
        q[3] = 0.25 * s;
    }
    return q;
}

unittest
{
    auto q1 = rotateQuaternionf(HALF_PI, normalizedVector(1.0f, 2.0f, 3.0f));
    auto m1 = q1.toMatrix;
    auto q2 = m1.toQuaternion;
    assert(aEqual(q1[], q2[]));
}

///
@trusted @nogc pure nothrow
Quaternion!PRECISION getQuaternionTo(PRECISION)
    (in auto ref PRECISION[3] from, in auto ref PRECISION[3] to)
{
    auto fl = length(from[0], from[1], from[2]);
    auto tl = length(to[0], to[1], to[2]);
    auto fl1 = 1 / fl;
    auto tl1 = 1 / tl;
    auto c = from.cross(to);
    if (0 < c.lengthSq) c.normalize;
    auto d = from.dot(to) * fl1 * tl1;
    auto k = (tl * fl1) ^^ 0.5;
    PRECISION cos2 = void, sin2 = void;
    if (-1 < d)
    {
        cos2 = (0.5 * (1 + d)) ^^ 0.5;
        sin2 = (0.5 * (1 - d)) ^^ 0.5;
    }
    else // gimbal lock
    {
        c = Vector3!PRECISION(from[2], from[0], from[1]);
        cos2 = 0;
        sin2 = 1;
    }
    return Quaternion!PRECISION(k * cos2, k * c.x * sin2, k * c.y * sin2
                               , k * c.z * sin2);
}

///
@trusted @nogc pure nothrow
Quaternion!PRECISION getQuaternionTo(PRECISION)
    (in auto ref PRECISION[3] from, in auto ref PRECISION[3] to
    , in auto ref PRECISION[3] axis)
{
    auto fl = length(from[0], from[1], from[2]);
    auto tl = length(to[0], to[1], to[2]);
    auto fl1 = 1 / fl;
    auto tl1 = 1 / tl;
    auto d = from.dot(to) * fl1 * tl1;
    auto k = (tl * fl1) ^^ 0.5;
    PRECISION cos2 = (0.5 * (1 + d)) ^^ 0.5;
    PRECISION sin2 = (0.5 * (1 - d)) ^^ 0.5;

    return Quaternion!PRECISION(k * cos2, k * axis[0] * sin2
                               , k * axis[1] * sin2, k * axis[2] * sin2);
}


unittest
{
    auto v1 = V3(1, 2, 3);
    auto v2 = V3(3, 4, 5);
    auto q1 = v1.getQuaternionTo(v2);
    auto v3 = q1 * v1;

    assert(aEqual(v2[], v3[]));

    v1 = V3(1, 0, 0);
    v2 = V3(1, 0, 0);
    assert(aEqual(v1.getQuaternionTo(v2)[], [1.0f, 0.0f, 0.0f, 0.0f]));
}
unittest
{
    auto v2 = V3(0, -1.52, 16);
    auto v1 = V3(0, 66.726, 0);
    auto v0 = V3(0, -1.52, 0);

    auto z = (v1 - v0).normalizedVector;
    auto x = (v2 - v0).cross(z).normalizedVector;
//    writeln(z[]);
//    writeln(x[]);

    auto r1 = z.getQuaternionTo([0.0f, 0.0f, 1.0f]);
//    writeln(r1[]);
    x = r1 * x;
//    writeln(x[]);
    auto xaxis = V3(1, 0, 0);
    auto zaxis = V3(0, 0, 1);
    auto r2 = x.getQuaternionTo(xaxis, zaxis) * r1;
//    writeln(r2[]);
}



//------------------------------------------------------------------------------
/// Matrix2
struct Matrix2(PRECISION)
{
    ///
    PRECISION[4] v = (){ PRECISION[4] n = void; _loadI(n); return n; }();
    alias v this;

    @trusted @nogc pure nothrow:
    ///
    this(in PRECISION s){ v[] = s; }
    ///
    this(in PRECISION[4] s...){ v[] = s[]; }
    ///
    this(in ref PRECISION[4] s){ v[] = s[]; }

    ///
    @property
    ref auto _11() inout { return v[0]; }
    /// ditto
    @property
    ref auto _12() inout { return v[1]; }
    /// ditto
    @property
    ref auto _21() inout { return v[2]; }
    /// ditto
    @property
    ref auto _22() inout { return v[3]; }

    //
    private void _mul(in ref PRECISION[4] s, out PRECISION[4] o) const
    {
        o[0] = v[0]*s[0] + v[2]*s[1];
        o[1] = v[1]*s[0] + v[3]*s[1];
        o[2] = v[0]*s[2] + v[2]*s[3];
        o[3] = v[1]*s[2] + v[3]*s[3];
    }

    ///
    Vector2!PRECISION opBinary(string OP : "*")(in PRECISION[2] s ...) const
    {
        return Vector2!PRECISION(v[0]*s[0] + v[2]*s[1]
                                , v[1]*s[0] + v[3]*s[1]);
    }

    ///
    Matrix2 opBinary(string OP : "*")(in auto ref PRECISION[4] s) const
    { Matrix2 o = void; _mul(s, o.v); return o; }
    /// ditto
    ref Matrix2 opOpAssign(string OP : "*")(in auto ref PRECISION[4] s)
    { PRECISION[4] n = void; _mul(s, n); v[] = n; return this; }

    static private void _loadI(out PRECISION[4] o)
    { o[0] = o[3] = 1; o[1] = o[2] = 0; }

    ///
    ref Matrix2 loadIdentity() {_loadI(v); return this; }
    ///
    static Matrix2 identityMatrix() { return Matrix2(); }

    static private void _rotate(in PRECISION a, out PRECISION[4] o)
    {
        creal cs;
        if (__ctfe) cs = cos(a) + sin(a) * 1.0i;
        else cs = expi(a);
        o[0] = cs.re; o[1] = cs.im;
        o[2] = -cs.im; o[3] = cs.re;
    }
    ///
    ref Matrix2 rotate(in PRECISION a)
    {
        PRECISION[4] r = void, n = void;
        _rotate(a, r);
        _mul(r, n);
        v[] = n;
        return this;
    }

    ///
    static Matrix2 rotateMatrix(in PRECISION a)
    { Matrix2 n = void; _rotate(a, n.v); return n; }


    static private void _scale(in PRECISION x, in PRECISION y
                              , out PRECISION[4] o)
    { o[1] = o[2] = 0; o[0] = x; o[3] = y;}
    ///
    ref Matrix2 scale(in PRECISION x, in PRECISION y)
    {
        PRECISION[4] s = void, n = void;
        _scale(x, y, s);
        _mul(s, n);
        v[] = n;
        return this;
    }

    /// ditto
    static Matrix2 scaleMatrix(in PRECISION x, in PRECISION y)
    { Matrix2 n = void; _scale(x, y, n.v); return n; }


    ///
    PRECISION determinant() const
    { return v[0]*v[3] - v[2]*v[1]; }

    ///
    Matrix2 inverseMatrix() const
    {
        PRECISION det = determinant;
        if (0 == det) return Matrix2(PRECISION.nan);
        PRECISION det1 = 1 / det;
        Matrix2 n = void;
        n[0] = v[3] * det1;
        n[1] = -v[1] * det1;
        n[2] = -v[2] * det1;
        n[3] = v[0] * det1;
        return n;
    }

}
alias Matrix2f = Matrix2!float;

/// suger
template identityMatrix2(PRECISION)
{ alias identityMatrix2 = Matrix2!PRECISION.identityMatrix; }
/// ditto
alias identityMatrix2f = identityMatrix2!float;

/// suger
template rotateMatrix2(PRECISION)
{ alias rotateMatrix2 = Matrix2!PRECISION.rotateMatrix; }
/// ditto
alias rotateMatrix2f = rotateMatrix2!float;

/// suger
template scaleMatrix2(PRECISION)
{ alias scaleMatrix2 = Matrix2!PRECISION.scaleMatrix; }
/// ditto
alias scaleMatrix2f = scaleMatrix2!float;

//------------------------------------------------------------------------------
/// Matrix3
struct Matrix3(PRECISION)
{
    ///
    PRECISION[9] v = (){ PRECISION[9] n = void; _loadI(n); return n; }();
    alias v this;

    @trusted @nogc pure nothrow:

    ///
    this(in PRECISION s){ v[] = s; }
    ///
    this(in PRECISION[9] s...){ v[] = s[]; }
    ///
    this(in ref PRECISION[9] s){ v[] = s[]; }

    @property
    {
        ///
        ref auto _11() inout { return v[0]; }
        /// ditto
        ref auto _12() inout { return v[1]; }
        /// ditto
        ref auto _13() inout { return v[2]; }
        /// ditto
        ref auto _21() inout { return v[3]; }
        /// ditto
        ref auto _22() inout { return v[4]; }
        /// ditto
        ref auto _23() inout { return v[5]; }
        /// ditto
        ref auto _31() inout { return v[6]; }
        /// ditto
        ref auto _32() inout { return v[7]; }
        /// ditto
        ref auto _33() inout { return v[8]; }
    }

    //
    private void _mul(in ref PRECISION[9] s, out PRECISION[9] o) const
    {
        o[0] = v[0]*s[0] + v[3]*s[1] + v[6]*s[2];
        o[1] = v[1]*s[0] + v[4]*s[1] + v[7]*s[2];
        o[2] = v[2]*s[0] + v[5]*s[1] + v[8]*s[2];

        o[3] = v[0]*s[3] + v[3]*s[4] + v[6]*s[5];
        o[4] = v[1]*s[3] + v[4]*s[4] + v[7]*s[5];
        o[5] = v[2]*s[3] + v[5]*s[4] + v[8]*s[5];

        o[6] = v[0]*s[6] + v[3]*s[7] + v[6]*s[8];
        o[7] = v[1]*s[6] + v[4]*s[7] + v[7]*s[8];
        o[8] = v[2]*s[6] + v[5]*s[7] + v[8]*s[8];
    }

    ///
    Vector2!PRECISION opBinary(string OP : "*")(in PRECISION[2] s ...) const
    {
        Vector2!PRECISION r = void;
        PRECISION w = 1 / (v[2]*s[0] + v[5]*s[1] + v[8]);
        r[0] = (v[0]*s[0] + v[3]*s[1] + v[6]) * w;
        r[1] = (v[1]*s[0] + v[4]*s[1] + v[7]) * w;
        return r;
    }

    ///
    Matrix3 opBinary(string OP : "*")(in auto ref PRECISION[9] s) const
    { Matrix3 o = void; _mul(s, o.v); return o; }
    /// ditto
    ref Matrix3 opOpAssign(string OP : "*")(in auto ref PRECISION[9] s)
    { PRECISION[9] n = void; _mul(s, n); v[] = n; return this; }

    static private void _loadI(out PRECISION[9] o)
    { o[] = 0; o[0] = o[4] = o[8] = 1; }

    ///
    ref Matrix3 loadIdentity() {_loadI(v); return this; }
    ///
    static Matrix3 identityMatrix() { return Matrix3(); }

    static private void _translate(in ref PRECISION[2] s, out PRECISION[9] o)
    {
        o[0] = 1; o[1] = 0; o[2] = 0;
        o[3] = 0; o[4] = 1; o[5] = 0;
        o[6] = s[0]; o[7] = s[1]; o[8] = 1;
    }

    ///
    ref Matrix3 translate(in PRECISION[2] s ...)
    {
        PRECISION[9] t = void, n = void;
        _translate(s, t);
        _mul(t, n);
        v[] = n;
        return this;
    }

    ///
    static Matrix3 translateMatrix(in PRECISION[2] s ...)
    { Matrix3 n = void; _translate(s, n.v); return n; }


    static private void _rotate(in PRECISION a, out PRECISION[9] o)
    {
        creal cs;
        if (__ctfe) cs = cos(a) + sin(a) * 1.0i;
        else cs = expi(a);
        o[0] = cs.re; o[1] = cs.im; o[2] = 0.0;
        o[3] = -cs.im; o[4] = cs.re; o[5] = 0.0;
        o[6] = 0.0; o[7] = 0.0; o[8] = 1.0;
    }
    ///
    ref Matrix3 rotate(in PRECISION a)
    {
        PRECISION[9] r = void, n = void;
        _rotate(a, r);
        _mul(r, n);
        v[] = n;
        return this;
    }

    ///
    static Matrix3 rotateMatrix(in PRECISION a)
    { Matrix3 n = void; _rotate(a, n.v); return n; }

    static private void _scale(in PRECISION x, in PRECISION y
                              , out PRECISION[9] o)
    { o[] = 0; o[0] = x; o[4] = y; o[8] = 1; }
    ///
    ref Matrix3 scale(in PRECISION x, in PRECISION y)
    {
        PRECISION[9] s = void, n = void;
        _scale(x, y, s);
        _mul(s, n);
        v[] = n;
        return this;
    }
    /// ditto
    static Matrix3 scaleMatrix(in PRECISION x, in PRECISION y)
    { Matrix3 n = void; _scale(x, y, n.v); return n; }

    ///
    PRECISION determinant() const
    {
        return v[0]*v[4]*v[8] + v[3]*v[7]*v[2] + v[6]*v[1]*v[5]
             - v[6]*v[4]*v[2] - v[3]*v[1]*v[8] - v[0]*v[7]*v[5];
    }

    ///
    Matrix3 inverseMatrix() const
    {
        PRECISION det = determinant;
        if (0 == det) return Matrix3(PRECISION.nan);
        PRECISION det1 = 1 / det;
        Matrix3 n = void;
        n[0] = (v[4]*v[8] - v[7]*v[5]) * det1;
        n[1] = (v[7]*v[2] - v[1]*v[8]) * det1;
        n[2] = (v[1]*v[5] - v[4]*v[2]) * det1;

        n[3] = (v[6]*v[5] - v[3]*v[8]) * det1;
        n[4] = (v[0]*v[8] - v[6]*v[2]) * det1;
        n[5] = (v[3]*v[2] - v[0]*v[5]) * det1;

        n[6] = (v[3]*v[7] - v[6]*v[4]) * det1;
        n[7] = (v[6]*v[1] - v[0]*v[7]) * det1;
        n[8] = (v[0]*v[4] - v[3]*v[1]) * det1;
        return n;
    }
}
/// ditto
alias Matrix3f = Matrix3!float;

/// suger
template identityMatrix3(PRECISION)
{ alias identityMatrix3 = Matrix3!PRECISION.identityMatrix; }
/// ditto
alias identityMatrix3f = identityMatrix3!float;

/// suger
template translateMatrix3(PRECISION)
{ alias translateMatrix3 = Matrix3!PRECISION.translateMatrix; }
/// ditto
alias translateMtrix3f = translateMatrix3!float;

/// suger
template rotateMatrix3(PRECISION)
{ alias rotateMatrix3 = Matrix3!PRECISION.rotateMatrix; }
/// ditto
alias rotateMatrix3f = rotateMatrix3!float;

unittest
{
    M3 m = M3.rotateMatrix(HALF_PI);
    V2 a = V2(1, 0);
    auto b = m * a;
    assert(aEqual(b[], [0, 1]));
    auto mi = m.inverseMatrix;
    assert(aEqual((mi * b)[], a[]));
}


//------------------------------------------------------------------------------
// Matrix4
/** 4x4 column-major matrix.
 *
 * <pre>
 *        | _11, _21, _31, _41 |   | 0,  4,  8,  12 |
 *    M = | _12, _22, _32, _42 | = | 1,  5,  9,  13 |
 *        | _13, _23, _33, _43 |   | 2,  6,  10, 14 |
 *        | _14, _24, _34, _44 |   | 3,  7,  11, 15 |
 * </pre>
 *
 * M[1] == M[0,1] == M._12;
 */
struct Matrix4(PRECISION)
{
    /// 中身
    PRECISION[16] v = (){ PRECISION[16] n = void; _loadI(n); return n; }();
    alias v this; //

    @trusted @nogc pure nothrow:

    // constructor
    ///
    this(PRECISION s){ v[] = s; }
    /// ditto
    this(in PRECISION[] s ...) { v[] = s; }
    /// ditto
    this(in ref PRECISION[] s) { v[] = s; }

    @property
    {
        ///
        ref auto _11() inout { return v[0]; }
        /// ditto
        ref auto _12() inout { return v[1]; }
        /// ditto
        ref auto _13() inout { return v[2]; }
        /// ditto
        ref auto _14() inout { return v[3]; }
        /// ditto
        ref auto _21() inout { return v[4]; }
        /// ditto
        ref auto _22() inout { return v[5]; }
        /// ditto
        ref auto _23() inout { return v[6]; }
        /// ditto
        ref auto _24() inout { return v[7]; }
        /// ditto
        ref auto _31() inout { return v[8]; }
        /// ditto
        ref auto _32() inout { return v[9]; }
        /// ditto
        ref auto _33() inout { return v[10]; }
        /// ditto
        ref auto _34() inout { return v[11]; }
        /// ditto
        ref auto _41() inout { return v[12]; }
        /// ditto
        ref auto _42() inout { return v[13]; }
        /// ditto
        ref auto _43() inout { return v[14]; }
        /// ditto
        ref auto _44() inout { return v[15]; }
    }

    @trusted @nogc pure nothrow
    bool isNaN() const
    {
        alias n = std.math.isNaN;
        return n(v[0]) || n(v[1]) || n(v[2]) || n(v[3])
            || n(v[4]) || n(v[5]) || n(v[6]) || n(v[7])
            || n(v[8]) || n(v[9]) || n(v[10]) || n(v[11])
            || n(v[12]) || n(v[13]) || n(v[14]) || n(v[15]);
    }

    // operator overloading
    ///
    Matrix4 transposedMatrix() const
    {
        return Matrix4(v[0], v[4], v[8],  v[12]
                      , v[1], v[5], v[9],  v[13]
                      , v[2], v[6], v[10], v[14]
                      , v[3], v[7], v[11], v[15]);
    }


    // matrix * matrix
    private void _mul(in ref PRECISION[16] s, out PRECISION[16] o) const
    {
        o[0] = (v[0]*s[0]) + (v[4]*s[1]) + (v[8]*s[2]) + (v[12]*s[3]);
        o[1] = (v[1]*s[0]) + (v[5]*s[1]) + (v[9]*s[2]) + (v[13]*s[3]);
        o[2] = (v[2]*s[0]) + (v[6]*s[1]) + (v[10]*s[2]) + (v[14]*s[3]);
        o[3] = (v[3]*s[0]) + (v[7]*s[1]) + (v[11]*s[2]) + (v[15]*s[3]);

        o[4] = (v[0]*s[4]) + (v[4]*s[5]) + (v[8]*s[6]) + (v[12]*s[7]);
        o[5] = (v[1]*s[4]) + (v[5]*s[5]) + (v[9]*s[6]) + (v[13]*s[7]);
        o[6] = (v[2]*s[4]) + (v[6]*s[5]) + (v[10]*s[6]) + (v[14]*s[7]);
        o[7] = (v[3]*s[4]) + (v[7]*s[5]) + (v[11]*s[6]) + (v[15]*s[7]);

        o[8] = (v[0]*s[8]) + (v[4]*s[9]) + (v[8]*s[10]) + (v[12]*s[11]);
        o[9] = (v[1]*s[8]) + (v[5]*s[9]) + (v[9]*s[10]) + (v[13]*s[11]);
        o[10] = (v[2]*s[8]) + (v[6]*s[9]) + (v[10]*s[10]) + (v[14]*s[11]);
        o[11] = (v[3]*s[8]) + (v[7]*s[9]) + (v[11]*s[10]) + (v[15]*s[11]);

        o[12] = (v[0]*s[12]) + (v[4]*s[13]) + (v[8]*s[14]) + (v[12]*s[15]);
        o[13] = (v[1]*s[12]) + (v[5]*s[13]) + (v[9]*s[14]) + (v[13]*s[15]);
        o[14] = (v[2]*s[12]) + (v[6]*s[13]) + (v[10]*s[14]) + (v[14]*s[15]);
        o[15] = (v[3]*s[12]) + (v[7]*s[13]) + (v[11]*s[14]) + (v[15]*s[15]);
    }

    ///
    Vector3!PRECISION opBinary(string OP : "*")(in auto ref PRECISION[3] s)
        const
    {
        Vector3!PRECISION r = void;
        PRECISION w = 1 / (v[3] * s[0] + v[7] * s[1] + v[11] * s[2] + v[15]);
        r[0] = (v[0] * s[0] + v[4] * s[1] + v[8] * s[2] + v[12]) * w;
        r[1] = (v[1] * s[0] + v[5] * s[1] + v[9] * s[2] + v[13]) * w;
        r[2] = (v[2] * s[0] + v[6] * s[1] + v[10] * s[2] + v[14]) * w;
        return r;
    }

    ///
    Matrix4 opBinary(string OP : "*")(in auto ref PRECISION[16] s) const
    { Matrix4 n = void; _mul(s, n.v); return n; }

    /// ditto
    ref Matrix4 opOpAssign(string OP : "*")(in auto ref PRECISION[16] s)
    { PRECISION[16] n = void; _mul(s, n); v[] = n; return this; }

    /// identity
    static private void _loadI(out PRECISION[16] o)
    { o[] = 0; o[0] = o[5] = o[10] = o[15] = 1; }
    ///
    ref Matrix4 loadIdentity() { _loadI(v); return this; }
    /// ditto
    static Matrix4 identityMatrix() { return Matrix4(); }

    // translation
    static private void _translate(in ref PRECISION[3] s
                                  , out PRECISION[16] o)
    { _loadI(o); o[12..15] = s; }
    ///
    ref Matrix4 translate(in PRECISION[3] s ...)
    {
        PRECISION[16] t = void, n = void;
        _translate(s, t);
        _mul(t, n);
        v[] = n;
        return this;
    }
    /// ditto
    ref Matrix4 translate(in ref PRECISION[3] s)
    {
        PRECISION[16] t = void, n = void;
        _translate(s, t);
        _mul(t, n);
        v[] = n;
        return this;
    }
    /// ditto
    static Matrix4 translateMatrix(in PRECISION[3] s ...)
    { Matrix4 n = void; _translate(s, n.v); return n; }
    /// ditto
    static Matrix4 translateMatrix(in ref PRECISION[3] s)
    { Matrix4 n = void; _translate(s, n.v); return n; }


    // rotation
    static private void _rotate(in PRECISION a, in ref PRECISION[3] r
                               , out PRECISION[16] o)
    {
        creal cs= expi(a);
        PRECISION c = cs.re;
        PRECISION s = cs.im;
        PRECISION c1 = 1-c;
        o[0] = (r[0]*r[0]*c1)+c;
        o[1] = (r[1]*r[0]*c1)+(r[2]*s);
        o[2] = (r[0]*r[2]*c1)-(r[1]*s);
        o[3] = 0;
        o[4] = (r[0]*r[1]*c1)-(r[2]*s);
        o[5] = (r[1]*r[1]*c1)+c;
        o[6] = (r[1]*r[2]*c1)+(r[0]*s);
        o[7] = 0;
        o[8] = (r[0]*r[2]*c1)+(r[1]*s);
        o[9] = (r[1]*r[2]*c1)-(r[0]*s);
        o[10] = (r[2]*r[2]*c1)+c;
        o[11..15] = 0;
        o[15] = 1;
    }
    ///
    ref Matrix4 rotate(PRECISION a, in PRECISION[3] s...)
    {
        PRECISION[16] r = void, n = void;
        _rotate(a, s, r);
        _mul(r, n);
        v[] = n;
        return this;
    }
    /// ditto
    ref Matrix4 rotate(PRECISION a, in ref PRECISION[3] s)
    {
        PRECISION[16] r = void, n = void;
        _rotate(a, s, r);
        _mul(r, n);
        v[] = n;
        return this ;
    }
    /// ditto
    static Matrix4 rotateMatrix(in PRECISION a, in PRECISION[3] r...)
    { Matrix4 n = void; _rotate(a, r, n.v); return n; }
    /// ditto
    static Matrix4 rotateMatrix(in PRECISION a, in ref PRECISION[3] r)
    { Matrix4 n = void; _rotate(a, r, n.v); return n; }

    static private void _rYZ(in PRECISION a, out PRECISION[16] o)
    {
        creal cs = expi(a); // cos(a)==cs.re; sin(a)==cs.im;
        o[0] = 1;
        o[1..5] = 0;
        o[5] = cs.re;
        o[6] = cs.im;
        o[7..9] = 0;
        o[9] = -cs.im;
        o[10] = cs.re;
        o[11..15] = 0.0;
        o[15] = 1;
    }
    ///
    ref Matrix4 rotateYZ(in PRECISION a)
    {
        PRECISION[16] r = void, n = void;
        _rYZ(a, r);
        _mul(r, n);
        v[] = n;
        return this;
    }
    /// ditto
    static Matrix4 rotateYZMatrix(in PRECISION a)
    { Matrix4 n = void; _rYZ(a, n.v); return n; }

    //
    static private void _rotZX(in PRECISION a, out PRECISION[16] o)
    {
        creal cs = expi(a);// cos(a)==cs.re; sin(a)==cs.im;
        o[0] = cs.re;
        o[1] = 0.0;
        o[2] = -cs.im;
        o[3..5] = 0.0;
        o[5] = 1;
        o[6..8] = 0;
        o[8] = cs.im;
        o[9] = 0.0;
        o[10] = cs.re;
        o[11..15] = 0;
        o[15] = 1;
    }
    ///
    ref Matrix4 rotateZX(in PRECISION a)
    {
        PRECISION[16] r = void, n = void;
        _rotZX(a, r);
        _mul(r, n);
        v[] = n;
        return this;
    }
    /// ditto
    static Matrix4 rotateZXMatrix(in PRECISION a)
    { Matrix4 n = void; _rotZX(a, n.v); return n; }

    static private void _rotXY(in PRECISION a, out PRECISION[16] o)
    {
        creal cs = expi(a); // cos(a)==cs.re; sin(a)==cs.im;
        o[0] = cs.re;
        o[1] = cs.im;
        o[2..4] = 0.0;
        o[4] = -cs.im;
        o[5] = cs.re;
        o[6..10] = 0.0;
        o[10] = 1;
        o[11..15] = 0;
        o[15] = 1;
    }
    ///
    ref Matrix4 rotateXY(in PRECISION a)
    {
        PRECISION[16] r = void, n = void;
        _rotXY(a, r);
        _mul(r, n);
        v[] = n;
        return this;
    }
    /// ditto
    static Matrix4 rotateXYMatrix(in PRECISION a)
    { Matrix4 n = void; _rotXY(a, n.v); return n; }

    // scaling
    static private void _scale(in ref PRECISION[3] s, out PRECISION[16] o)
    {
        o[] = 0;
        o[0] = s[0];
        o[5] = s[1];
        o[10] = s[2];
        o[15] = 1;
    }
    ///
    ref Matrix4 scale(in PRECISION[3] s...)
    {
        PRECISION[16] m = void, n = void;
        _scale(s, m);
        _mul(m, n);
        v[] = n;
        return this;
    }
    /// ditto
    ref Matrix4 scale(in ref PRECISION[3] s)
    {
        PRECISION[16] m = void, n = void;
        _scale(s, m);
        _mul(m, n);
        v[] = n;
        return this;
    }
    /// ditto
    static Matrix4 scaleMatrix(in PRECISION[3] s...)
    { Matrix4 n = void; _scale(s, n.v); return n; }
    /// ditto
    static Matrix4 scaleMatrix(in ref PRECISION[3] s)
    { Matrix4 n = void; _scale(s, n.v); return n; }

    ///
    Vector3!PRECISION getScale() const
    {
        return Vector3!PRECISION(Vector3!PRECISION(v[0..3]).length
                                , Vector3!PRECISION(v[4..7]).length
                                , Vector3!PRECISION(v[8..11]).length);
    }

    // projection
    ///
    static Matrix4 orthoMatrix(in PRECISION l, in PRECISION r
                              , in PRECISION b, in PRECISION t
                              , in PRECISION n, in PRECISION f)
    {
        auto rl1 = 1 / (r - l);
        auto tb1 = 1 / (t - b);
        auto fn1 = 1 / (f - n);
        return Matrix4(2 * rl1,      0.0,          0.0,          0.0
                      , 0.0,          2 * tb1,      0.0,          0.0
                      , 0.0,          0.0,          -2 * fn1,     0.0
                      , -(r+l) * rl1, -(t+b) * tb1, -(f+n) * fn1, 1.0);
    }


    ///
    static Matrix4 frustumMatrix(in PRECISION width, in PRECISION height
                                , in  PRECISION near, in PRECISION far)
    {
        PRECISION fn1 = 1/(far-near);
        return Matrix4(2*near/width, 0.0,           0.0,              0.0
                      , 0.0,          2*near/height, 0.0,              0.0
                      , 0.0,          0.0,           -(far+near)*fn1, -1.0
                      , 0.0,          0.0,           -2*far*near*fn1,  0.0);
    }
    ///
    static Matrix4 frustumMatrixLH(in PRECISION width, in PRECISION height
                                  , in PRECISION near, in PRECISION far)
    {
        PRECISION fn1 = 1/(far-near);
        return Matrix4(-2*near/width, 0.0,            0.0,             0.0
                      , 0.0,           -2*near/height, 0.0,             0.0
                      , 0.0,           0.0,            -(far+near)*fn1, 1.0
                      , 0.0,           0.0,            2*far*near*fn1,  1.0);
    }

    ///
    static Matrix4 perspectiveMatrix(in PRECISION fovy, in PRECISION asp
                                    , in PRECISION near, in PRECISION far)
    {
        PRECISION f = 1/(tan(fovy*0.5*TO_RADIAN));
        PRECISION fn1 = 1/(far-near);
        return Matrix4(f/asp, 0.0, 0.0,              0.0
                      , 0.0,   f,   0.0,              0.0
                      , 0.0,   0.0, -(far+near)*fn1, -1.0
                      , 0.0,   0.0, -2*far*near*fn1,  0.0);
    }

    ///
    static Matrix4 perspectiveMatrixLH(in PRECISION fovy, in PRECISION asp
                                      , in PRECISION near, in PRECISION far)
    {
        PRECISION f = 1/(tan(fovy*0.5*TO_RADIAN));
        PRECISION nf = 1/(far-near);
        return Matrix4(f/asp, 0.0, 0.0,              0.0
                      , 0.0,   f,   0.0,              0.0
                      , 0.0,   0.0, -1*(far+near)*nf, 1.0
                      , 0.0,   0.0, 2*far*near*nf,    1.0);
    }

    /// viewing
    static Matrix4 lookForMatrix()(in auto ref PRECISION[3] lf
                                  , in auto ref PRECISION[3] up)
    {
        Vector3!PRECISION z = Vector3!PRECISION(-lf[0], -lf[1], -lf[2]);
        z.normalize;
        Vector3!PRECISION x = cross(up,z);
        x.normalize;
        Vector3!PRECISION y = cross(z,x);

        return Matrix4(x.x, y.x, z.x, 0
                      , x.y, y.y, z.y, 0
                      , x.z, y.z, z.z, 0
                      , 0,   0,   0,   1);
    }

    ///
    static Matrix4 lookAtMatrix()(in auto ref PRECISION[3] eye
                                 , in auto ref PRECISION[3] center
                                 , in auto ref PRECISION[3] up)
    {
        Vector3!PRECISION z = Vector3!(PRECISION)(eye) - center;
        z.normalize;
        Vector3!PRECISION x = cross(up,z);
        x.normalize;
        Vector3!PRECISION y = cross(z,x);

        auto e = Vector3!(PRECISION)(-x.x*eye[0]-x.y*eye[1]-x.z*eye[2]
                                    , -y.x*eye[0]-y.y*eye[1]-y.z*eye[2]
                                    , -z.x*eye[0]-z.y*eye[1]-z.z*eye[2]);

        return Matrix4(x.x, y.x, z.x, 0
                      , x.y, y.y, z.y, 0
                      , x.z, y.z, z.z, 0
                      , e.x, e.y, e.z, 1);
    }

    /// inverse system
    PRECISION determinant() const
    {
        return (v[0]*v[5]*v[10]*v[15]) + (v[0]*v[9]*v[14]*v[7])
             + (v[0]*v[13]*v[6]*v[11]) + (v[4]*v[1]*v[14]*v[11])
             + (v[4]*v[9]*v[2]*v[15]) + (v[4]*v[13]*v[10]*v[3])
             + (v[8]*v[1]*v[6]*v[15]) + (v[8]*v[5]*v[14]*v[3])
             + (v[8]*v[13]*v[2]*v[7]) + (v[12]*v[1]*v[10]*v[7])
             + (v[12]*v[5]*v[2]*v[11]) + (v[12]*v[9]*v[6]*v[3])

             - (v[0]*v[5]*v[14]*v[11]) - (v[0]*v[9]*v[6]*v[15])
             - (v[0]*v[13]*v[10]*v[7]) - (v[4]*v[1]*v[10]*v[15])
             - (v[4]*v[9]*v[14]*v[3]) - (v[4]*v[13]*v[2]*v[11])
             - (v[8]*v[1]*v[14]*v[7]) - (v[8]*v[5]*v[2]*v[15])
             - (v[8]*v[13]*v[6]*v[3]) - (v[12]*v[1]*v[6]*v[11])
             - (v[12]*v[5]*v[10]*v[3]) - (v[12]*v[9]*v[2]*v[7]);
    }

    ///
    Matrix4 inverseMatrix() const
    {
        auto det1 = 1 / determinant;

        return Matrix4(
           // _11
           (v[5]*v[10]*v[15] + v[9]*v[14]*v[7] + v[13]*v[6]*v[11]
           - v[5]*v[14]*v[11] - v[9]*v[6]*v[15] - v[13]*v[10]*v[7]) * det1

           // _12
         , (v[1]*v[14]*v[11] + v[9]*v[2]*v[15] + v[13]*v[10]*v[3]
           - v[1]*v[10]*v[15] - v[9]*v[14]*v[3] - v[13]*v[2]*v[11]) * det1

           // _13
         , (v[1]*v[6]*v[15]  + v[5]*v[14]*v[3] + v[13]*v[2]*v[7]
           - v[1]*v[14]*v[7]  - v[5]*v[2]*v[15] - v[13]*v[6]*v[3]) * det1

           // _14
         , (v[1]*v[10]*v[7]  + v[5]*v[2]*v[11] + v[9]*v[6]*v[3]
           - v[1]*v[6]*v[11]  - v[5]*v[10]*v[3] - v[9]*v[2]*v[7]) * det1


           // _21
         , (v[4]*v[14]*v[11] + v[8]*v[6]*v[15] + v[12]*v[10]*v[7]
           - v[4]*v[10]*v[15] - v[8]*v[14]*v[7] - v[12]*v[6]*v[11]) * det1

           // _22
         , (v[0]*v[10]*v[15] + v[8]*v[14]*v[3] + v[12]*v[2]*v[11]
           - v[0]*v[14]*v[11] - v[8]*v[2]*v[15] - v[12]*v[10]*v[3]) * det1

           // _23
         , (v[0]*v[14]*v[7]  + v[4]*v[2]*v[15] + v[12]*v[6]*v[3]
           - v[0]*v[6]*v[15]  - v[4]*v[14]*v[3] - v[12]*v[2]*v[7]) * det1

           // _24
         , (v[0]*v[6]*v[11]  + v[4]*v[10]*v[3] + v[8]*v[2]*v[7]
           - v[0]*v[10]*v[7]  - v[4]*v[2]*v[11] - v[8]*v[6]*v[3]) * det1


           // _31
         , (v[4]*v[9]*v[15]  + v[8]*v[13]*v[7] + v[12]*v[5]*v[11]
           - v[4]*v[13]*v[11] - v[8]*v[5]*v[15] - v[12]*v[9]*v[7]) * det1

           // _32
         , (v[0]*v[13]*v[11] + v[8]*v[1]*v[15] + v[12]*v[9]*v[3]
           - v[0]*v[9]*v[15]  - v[8]*v[13]*v[3] - v[12]*v[1]*v[11]) * det1

           // _33
         , (v[0]*v[5]*v[15]  + v[4]*v[13]*v[3] + v[12]*v[1]*v[7]
           - v[0]*v[13]*v[7]  - v[4]*v[1]*v[15] - v[12]*v[5]*v[3]) * det1

           // _34
         , (v[0]*v[9]*v[7]   + v[4]*v[1]*v[11] + v[8]*v[5]*v[3]
           - v[0]*v[5]*v[11]  - v[4]*v[9]*v[3]  - v[8]*v[1]*v[7]) * det1


           // _41
         , (v[4]*v[13]*v[10] + v[8]*v[5]*v[14] + v[12]*v[9]*v[6]
           - v[4]*v[9]*v[14]  - v[8]*v[13]*v[6] - v[12]*v[5]*v[10]) * det1

           // _42
         , (v[0]*v[9]*v[14]  + v[8]*v[13]*v[2] + v[12]*v[1]*v[10]
           - v[0]*v[13]*v[10] - v[8]*v[1]*v[14] - v[12]*v[9]*v[2]) * det1

           // _43
         , (v[0]*v[13]*v[6]  + v[4]*v[1]*v[14] + v[12]*v[5]*v[2]
           - v[0]*v[5]*v[14]  - v[4]*v[13]*v[2] - v[12]*v[1]*v[6]) * det1

           // _44
         , (v[0]*v[5]*v[10]  + v[4]*v[9]*v[2]  + v[8]*v[1]*v[6]
           - v[0]*v[9]*v[6]   - v[4]*v[1]*v[10] - v[8]*v[5]*v[2]) * det1
);
    }
}
/// ditto
alias Matrix4!double Matrix4d;
/// ditto
alias Matrix4!float Matrix4f;

/// suger
template identityMatrix4(PRECISION)
{ alias identityMatrix4 = Matrix4!PRECISION.identityMatrix; }
/// ditto
alias identityMatrix4f = identityMatrix4!float;

///
template translateMatrix4(PRECISION)
{ alias translateMatrix4 = Matrix4!PRECISION.translateMatrix; }
/// ditto
alias translateMatrix4f = translateMatrix4!float;

///
template rotateMatrix4(PRECISION)
{ alias rotateMatrix4 = Matrix4!PRECISION.rotateMatrix; }
/// ditto
alias rotateMatrix4f = rotateMatrix4!float;

///
template rotateYZMatrix4(PRECISION)
{ alias rotateYZMatrix4 = Matrix4!PRECISION.rotateYZMatrix; }
/// ditto
alias rotateYZMatrix4f = rotateYZMatrix4!float;

///
template rotateZXMatrix4(PRECISION)
{ alias rotateZXMatrix4 = Matrix4!float.rotateZXMatrix; }
/// ditto
alias rotateZXMatrix4f = rotateZXMatrix4!float;

///
template rotateXYMatrix4(PRECISION)
{ alias rotateXYMatrix4 = Matrix4!PRECISION.rotateXYMatrix; }
/// ditto
alias rotateXYMatrix4f = rotateXYMatrix4!float;

///
template scaleMatrix4(PRECISION)
{ alias scaleMatrix4 = Matrix4!PRECISION.scaleMatrix; }
/// ditto
alias scaleMatrix4f = scaleMatrix4!float;

///
template orthoMatrix4(PRECISION)
{ alias orthoMatrix4 = Matrix4!PRECISION.orthoMatrix; }
/// ditto
alias orthoMatrix4f = orthoMatrix4!float;

///
template frustumMatrix4(PRECISION)
{ alias frustumMatrix4 = Matrix4!PRECISION.frustumMatrix; }
/// ditto
alias frustumMatrix4f = frustumMatrix4!float;

///
template perspectiveMatrix4(PRECISION)
{ alias perspectiveMatrix4 = Matrix4!PRECISION.perspectiveMatrix; }
/// ditto
alias perspectiveMatrix4f = perspectiveMatrix4!float;

///
template lookForMatrix4(PRECISION)
{ alias lookForMatrix4 = Matrix4!PRECISION.lookForMatrix; }
/// ditto
alias lookForMatrix4f = lookForMatrix4!float;

///
template lookAtMatrix4(PRECISION)
{ alias lookAtMatrix4 = Matrix4!PRECISION.lookAtMatrix; }
/// ditto
alias lookAtMatrix4f = lookAtMatrix4!float;


unittest
{
    auto mat = M4.perspectiveMatrix(45, 1, 1, 3) * M4.lookAtMatrix(V3(0, 0, 1), V3(0, 0, 0), V3(0, 1, 0));;
    auto v = V3(0, 0, -2);
    auto v2 = mat * v;
    writeln(v2);
}

unittest
{
    auto v = V3(1, 1, 1);
    auto v2 = v;
    auto m1 = M4.translateMatrix(1.0, 2.0, 3.0).rotate(0.1, 1.2, 0.3, -1.0).scale(0.3, 0.4, 1.3);
    v = m1 * v;
    auto inv_m1 = m1.inverseMatrix();
    v = inv_m1 * v;
    assert(aEqual(v[], v2[]));

    auto m2 = M4.frustumMatrix(680, 480, 1.0, -1.0);
    auto m3 = M4.perspectiveMatrix(cast(float)(HALF_PI * 0.5), 4 / 3, -1.0, 1.0);
    auto m4 = M4.lookAtMatrix([100.0f, 200.0f, 300.0f], [0.0f, 0.0f, 0.0f], [0.0f, 1.0f, 0.0f]);
}


//==============================================================================

/// Matrix4 を、平行移動、回転移動、拡大縮小に分解して格納する。
struct TRS(PRECISION)
{
    Vector3!PRECISION translate; ///
    Quaternion!PRECISION rotate; ///
    Vector3!PRECISION scale;     ///

    @trusted @nogc pure nothrow:

    ///
    Matrix4!PRECISION toMatrix()
    {
        return translateMatrix4!PRECISION(translate)
             * rotate.toMatrix
             * scaleMatrix4!PRECISION(scale);
    }

    ///
    bool approxEquals(in ref TRS r) const
    {
        import std.math : approxEqual;
        return approxEqual(translate[], r.translate[])
            && approxEqual(rotate[], r.rotate[])
            && approxEqual(scale[], r.scale[]);
    }
}
alias TRSf = TRS!float;

/**
 * Note:
 *   クォータニオンの回転方向が必ず正の値(軸に対して時計回りの回転)
 *   として返るので注意。
 */
@trusted @nogc pure nothrow
TRS!PRECISION toTRS(PRECISION)(in auto ref Matrix4!PRECISION mat)
{
    TRS!PRECISION trs;
    trs.scale = mat.getScale;


    auto temp = mat * Matrix4!PRECISION.scaleMatrix(
          approxEqual(trs.scale[0], 0) ? 0 : 1 / trs.scale[0]
        , approxEqual(trs.scale[1], 0) ? 0 : 1 / trs.scale[1]
        , approxEqual(trs.scale[2], 0) ? 0 : 1 / trs.scale[2]);

    trs.rotate = temp.toQuaternion;
    temp *= trs.rotate.conjugate.toMatrix;
    trs.translate = Vector3!PRECISION(temp[12..15]);
    return trs;
}

///
@trusted @nogc pure nothrow
TRS!PRECISION interpolateLinear(PRECISION)
    (in auto ref TRS!PRECISION a, PRECISION r, in auto ref TRS!PRECISION b)
{
    return TRS!PRECISION(interpolateLinear(a.translate, r, b.translate)
                        , interpolateLinear(a.rotate, r, b.rotate)
                        , interpolateLinear(a.scale, r, b.scale));
}

unittest
{
    auto trs = TRSf(Vector3f(3, 4, 5)
                   , rotateQuaternionf(45*TO_RADIAN
                     , Vector3f(1, 1, 3).normalizedVector)
                   , Vector3f(1, 2, 3));
    auto trs2 = trs.toMatrix.toTRS;
    assert(trs.approxEquals(trs2));
}


//==============================================================================
///
struct Arrow(PRECISION)
{
    Vector3!(PRECISION) p; ///
    Vector3!(PRECISION) v; ///

    ///
    @trusted @nogc pure nothrow
    this(in PRECISION[3] p, in PRECISION[3] v){ this.p = p; this.v = v; }
}
/// ditto
alias Arrow!float Arrowf;
///
@trusted @nogc pure nothrow
PRECISION distance(PRECISION)(in Arrow!PRECISION a, in Arrow!PRECISION b)
{ return (a.v.cross(b.v)).dot(b.p - a.p).abs; }


//------------------------------------------------------------------------------
/// マウス座標をワールド座標に。
class MouseArrow(PRECISION)
{
    private int viewportLeft, viewportTop;
    private PRECISION window2_width, window2_height;
    private Matrix4!PRECISION inv;
    Arrow!PRECISION arr; ///
    alias arr this; ///

    @trusted @nogc pure nothrow:
    ///
    this(int wx, int wy, int ww, int wh)
    { update(wx, wy, ww, wh); }

    ///
    void update(int wx, int wy, int ww, int wh)
    {
        viewportLeft = wx; viewportTop = wy;
        window2_width = 2.0 / (cast(PRECISION)ww);
        window2_height = 2.0 / (cast(PRECISION)wh);
    }

    ///
    void update(in ref Matrix4!PRECISION mat)
    { inv = mat.inverseMatrix; }

    ///
    ref Arrow!PRECISION opCall(int mx, int my)
    {
        auto x =   (mx - viewportLeft) * window2_width  - 1.0;
        auto y = - (my - viewportTop)  * window2_height + 1.0;
        arr.p = inv * Vector3!PRECISION(x, y, -1);
        arr.v = inv * Vector3!PRECISION(x, y, 1);
        arr.v -= arr.p;
        arr.v.normalize;
        return arr;
    }
}
///
alias MouseArrowf = MouseArrow!float;

//------------------------------------------------------------------------------
/// マウスでグリグリ動かせるマトリクス
interface TIViewerMatrix(PRECISION)
{
    /// 現在のマトリクスを得る。
    Matrix4!PRECISION matrix() @property const;

    /// マウス操作でグリグリする。dy は下向きが正。
    Matrix4!PRECISION rotate(int dx, int dy);
    /// ditto
    Matrix4!PRECISION shift(int dx, int dy);
    /// ditto
    Matrix4!PRECISION zoom(int d);
}

//------------------------------------------------------------------------------
/// マウスでグリグリ動くけど、上方向は変わらないマトリクスを管理する。
class TViewerMatrixA(PRECISION) : TIViewerMatrix!PRECISION
{
    private Matrix4!PRECISION _proj;
    private Polar3!PRECISION _pos;
    private Vector3!PRECISION _center;
    private const PRECISION SENSITIVITY;
    private enum Y = Vector3!PRECISION(0, 1, 0);

    @trusted @nogc pure nothrow:

    /// 初期状態では、Z軸正の方向、radius の位置から原点を見る。
    this(in Matrix4!PRECISION projection, PRECISION radius
        , in Vector3!PRECISION c = Vector3!PRECISION(0, 0, 0)
        , PRECISION s = 0.02)
    {
        _proj = projection;
        _pos = Polar3!PRECISION(-HALF_PI, 0, radius);
        _center = c;
        SENSITIVITY = s;
    }

    ///
    this(PRECISION s = 0.02)
    {
        _proj = Matrix4!PRECISION.identityMatrix;
        _pos = Polar3!PRECISION(-HALF_PI, 0, 1);
        _center = Vector3!PRECISION(0, 0, 0);
        SENSITIVITY = s;
    }

    ///
    ref auto projection() inout { return _proj; }
    ///
    ref auto center() inout { return _center; }
    ///
    ref auto radius() inout { return _pos.radius; }

    ///
    Matrix4!PRECISION matrix() const
    {
        return _proj * lookAtMatrix4!PRECISION(_pos.toVector + _center
                                              , _center, Y);
    }

    ///
    Matrix4!PRECISION rotate(int dx, int dy)
    {
        _pos.longitude += -dx * SENSITIVITY;
        _pos.longitude %= DOUBLE_PI;
        _pos.latitude += dy * SENSITIVITY;
        if      (HALF_PI <= _pos.latitude) _pos.latitude = HALF_PI * 0.99;
        else if (_pos.latitude <= -HALF_PI) _pos.latitude = - HALF_PI * 0.99;
        return matrix;
    }

    ///
    Matrix4!PRECISION shift(int dx, int dy)
    {
        auto c = Polar3!PRECISION(_pos.longitude, _pos.latitude, 1).toVector;
        auto ax = Y.cross(c);
        auto ay = c.cross(ax);
        _center += ((-ax * dx) + (ay * dy)) * (SENSITIVITY * _pos.radius * 0.1);
        return matrix;
    }

    ///
    Matrix4!PRECISION zoom(int d)
    {
        _pos.radius *= 1f + ((cast(float)d) / 10f);
        return matrix;
    }
}
/// ditto
alias ViewerMatrixAf = TViewerMatrixA!float;

///
class TViewerMatrixB(PRECISION) : TIViewerMatrix!PRECISION
{
    private Matrix4!PRECISION proj;
    private Vector3!PRECISION pos;
    private Vector3!PRECISION center;
    private const PRECISION SENSITIVITY;

    @trusted @nogc pure nothrow:

    /// 初期状態では、Z軸正の方向、radius の位置から原点を見る。
    this(in Matrix4!PRECISION projection, float z, PRECISION s = 0.02)
    {
        proj = projection;
        pos = Vector3!PRECISION(0, 0, z);
        SENSITIVITY = s;
        center = Vector3!PRECISION(0, 0, 0);
    }

    ///
    @property
    Matrix4!PRECISION matrix() const
    {
        return proj * Matrix4!PRECISION.lookAtMatrix(pos + center, center, Y);
    }

    ///
    Matrix4!PRECISION rotate(int dx, int dy)
    {
        // pos.longitude += -dx * SENSITIVITY;
        // pos.longitude %= DOUBLE_PI;
        // pos.latitude += dy * SENSITIVITY;
        // if      (HALF_PI <= pos.latitude) pos.latitude = HALF_PI * 0.99;
        // else if (pos.latitude <= -HALF_PI) pos.latitude = - HALF_PI * 0.99;
        return matrix;
    }

    ///
    Matrix4!PRECISION shift(int dx, int dy)
    {
        // auto c = Polar3!PRECISION(pos.longitude, pos.latitude, 1).toVector;
        // auto ax = Y.cross(c);
        // auto ay = c.cross(ax);
        // center += ((-ax * dx) + (ay * dy)) * (SENSITIVITY * pos.radius * 0.1);
        return matrix;
    }

    ///
    Matrix4!PRECISION zoom(int d)
    {
        // pos.radius *= 1f + ((cast(float)d) / 10f);
        return matrix;
    }
}

//==============================================================================
//
// あたり判定
//
//==============================================================================
//------------------------------------------------------------------------------
/// 直線とポリゴンの交差状態を格納する。
struct HitState(PRECISION)
{
    /// 点とポリゴンとの交点の距離
    PRECISION distance = PRECISION.max;

    /**
     * 点から見てポリゴンが時計回りの時 -&gt; true
     * OpenGL系では、点から見てポリゴンが時計回りの時は、
     * その点はポリゴンの裏側にある。
     */
    bool clockwise = false;
}

//------------------------------------------------------------------------------
/**
 * 無限直線 arr が、TRIANGLE を形成する face、 vertex と交差するか、
 * どう交差するか？(表から？裏から？)を判定している。$(BR)
 * 点 arr.p が TRIANGLE表面上にあり、直線 arr.v がポリゴン平面と平行の場合、
 * 直線は「TRIANGLE表から」「交差」と判定される。$(BR)
 * 点 arr.p が TRIANGLE表面上になく、直線 arr.v が TRIANGLE表面と平行に
 * TRIANGLE表面上を通る場合、直線は「交差なし」と判定される。$(BR)
 * それ以外の場合、TRIANGLE表面、境界および頂点上は「交差」と判定される。$(BR)
 *
 * Params:
 *   hs     = hs に予め収められている距離より近かった場合のみ、
 *            これを更新する。$(BR)
 *            表裏が同じ距離にあった場合、表を優先する。$(BR)
 *   arr    = 調べたい直線。arr.v は正規化されているものとする。$(BR)
 *            正規化されていない場合、表裏判定は同じだが hs.dist の値は
 *            デタラメになる。$(BR)
 *   face   = TRIANGLEを定義するインデックス配列$(BR)
 *   vertex = TRIANGLEを成形する頂点配列$(BR)
 *
 * Throws:
 *   face.length < 3 もしくは face が示す先より vertex が短かかった場合、
 *   Range violation が投げられる。
 */
@trusted @nogc pure nothrow
void crossState(PRECISION)(ref HitState!PRECISION hs
                          , ref const(Arrow!PRECISION) arr
                          , in Vector3!PRECISION[] vertex
                          , in uint[] face)
{
    Vector3!PRECISION v1, v2, v3, c1, c2, c3, v12, v23, v31;
    PRECISION d, c12, c23, c31;
    PRECISION dist = PRECISION.max;
    v1 = vertex[face[0]] - arr.p;
    v2 = vertex[face[1]] - arr.p;
    v3 = vertex[face[2]] - arr.p;
    c1 = arr.v.cross(v1);
    c2 = arr.v.cross(v2);
    c3 = arr.v.cross(v3);

    // ポリゴンと無限直線が、交差すると仮定する。………………… (1)
    // 仮定(1) より、c12、c23、c31 の符号は同じである。………… (2)
    // もしくは、点Pがポリゴン平面上にある場合は、
    // c12, c23, c31 は全て0である。 ………………………………… (3)

    // 符号がちがう場合、仮定(2)=仮定(1) に反するので、交差していない。
    c12 = c1.cross(c2).dot(arr.v);
    c23 = c2.cross(c3).dot(arr.v);
    if ((c12 * c23) < 0) return;
    c31 = c3.cross(c1).dot(arr.v);
    if ((c12 * c31) < 0) return;
    if ((c23 * c31) < 0) return;

    // 仮定(2) が満たされたので、交差している。
    // もしくは、点 p はポリゴン平面上にある。

    if (0 == c12 && 0 == c23 && 0 == c31) // 点 arr.p がポリゴン平面上にある。
    {
        // 点 arr.p がポリゴン面上にある場合はヒット、でなければスルー
        v12 = v1.cross(v2);
        v23 = v2.cross(v3);
        if (v12.dot(v23) <= 0) return;
        v31 = v3.cross(v1);
        if (v23.dot(v31) <= 0) return;

        dist = 0;
        d = 0;
    }
    else // 直線はポリゴンと交差
    {
        alias v12 v21;
        alias v23 nc213;
        v21 = v2 - v1;
        v31 = v3 - v1;
        nc213 = v21.cross(v31).normalizedVector;
        d = v1.dot(nc213);
        dist = abs(d / arr.v.dot(nc213));
    }
    if     (dist < hs.distance)
    {
        hs.distance = dist;
        // 点から見えるのは裏か表か？
        // 0 <= d に書き替えると境界上がポリゴン内となる。
        hs.clockwise = 0 < d;
    }
    // 同じ距離だった場合は表優先。これはメッシュの角などで起り得る。
    // approxEqualを使うべき？
    else if (dist == hs.distance)
    {
        hs.clockwise = hs.clockwise && 0 < d;
    }
}

//------------------------------------------------------------------------------
/**
 * 点 p がメッシュの内側にあるかどうか？どの位の深さにあるか？を測定する。$(BR)
 * メッシュは閉じており、(OpenGL的に)表裏が正しいと仮定する。$(BR)
 * (OpenGL では反時計回り順のポリゴンが表)$(BR)
 * 任意方向での最寄りのポリゴンの裏が見えているかどうかを判定している。$(BR)
 * 裏が見えていれば、点はメッシュの内にある。$(BR)
 * 境界上は外側となる。$(BR)
 *
 * Merit:
 *     ポリゴンとの交差回数をカウントする方式だと、点 p から伸ばした直線が
 *     トライアングルの境界を貫くような場合、処理が複雑になってしまう。
 * Demerit:
 *     OpenGL的に表裏が正しいポリゴンでないと処理が失敗する。
 *
 * Params:
 *   arr    = arr.p が対象の点。arr.v が、どの方向での深さを調べるかを示す。
 *   vertex = メッシュを構成する。
 *   index  = メッシュを定義する。
 * Returns:
 *   深さが返る。点がメッシュに含まれなかった場合は、負の数が返る。
 */
@trusted @nogc pure nothrow
PRECISION depthIn(PRECISION)
    (in Arrow!PRECISION arr, in Vector3!PRECISION[] vertex, in uint[] index)
{
    HitState!PRECISION hs;
    for (size_t i = 0 ; i+3 <= index.length ; i+=3)
        hs.crossState(arr, vertex, index[i .. $]);

    return hs.clockwise ? hs.distance : -hs.distance;
}

/** トライアングルが裏か表か。裏の場合、true。
 * p から見て vertex[index[0]], vertex[index[1]], vertex[index[2]]
 * の裏が見えている場合は
**/
@trusted @nogc pure nothrow
bool clockwise(PRECISION)
    (in Vector3!PRECISION p, in Vector3!PRECISION[] v, in uint[] i)
{
    auto a = v[i[0]] - p;
    auto n = cross(v[i[1]] - v[i[0]], v[i[2]] - v[i[0]]);
    return 0 <= dot(a, n);
}

unittest
{
    import std.conv : to;
    auto vert = [Vector3f(-1, 1, 1), Vector3f(1, 1, 1), Vector3f(1, 1, -1), Vector3f(-1, 1, -1)
                , Vector3f(-1, -1, 1), Vector3f(1, -1, 1), Vector3f(1, -1, -1), Vector3f(-1, -1, -1)];
    uint[] idx = [0, 4, 5, 0, 5, 1, 0, 1, 2, 0, 2, 3, 0, 3, 7, 0, 7, 4
                 , 6, 2, 1, 6, 1, 5, 6, 5, 4, 6, 4, 7, 6, 7, 3, 6, 3, 2];
    alias A = Arrow!float;

    assert(0 < A([0, 0, 0], [0, 1, 0]).depthIn!float(vert, idx));
    assert(0 < A([0.9, 0.9, -0.7], [0, 1, 0]).depthIn!float(vert, idx));
    assert(0 < A([0.9, 0.9, 0.9], [0, 1, 0]).depthIn!float(vert, idx));
    assert(0 < A([-0.9, 0.9, 0.9], [0, 1, 0]).depthIn!float(vert, idx));
    assert(0 < A([1.0, 0.0, 0.0], [0, 1, 0]).depthIn!float(vert, idx));
    assert(0 >= A([-1.0, 1.0, 1.0], [0, 1, 0]).depthIn!float(vert, idx));
    assert(0 >= A([1.0, 1.0, 1.0], [0, 1, 0]).depthIn!float(vert, idx));

    assert(0 >= A([0.0, 10, 0.0], [0, 1, 0]).depthIn!float(vert, idx));
}



//==============================================================================
/** 原点を中心とし、各辺の長さが2の立方体。
 *
 * $(LINK #sworks.base.matrix.Arrow)との当り判定を取れる。
**/
interface IdentityGeom(PRECISION)
{
    private alias V = Vector3!PRECISION;

    // Identity Cube. 原点を中心とし、各辺の長さが 2 の立方体
    enum VERTEX =
        [V(-1, 1, 1), V(-1, -1, 1), V(1, -1, 1), V(1, 1, 1), V(-1, 1, -1)
        , V(-1, -1, -1), V(1, -1, -1), V(1, 1, -1)];

    enum INDEX_LINE =
        [0u, 1, 1, 2, 2, 3, 3, 0
        , 4, 5, 5, 6, 6, 7, 7, 4
        , 0, 4, 3, 7, 2, 6, 1, 5];
    enum INDEX_POLY =
        [0u, 1, 3,  1, 2, 3,  3, 2, 7,  2, 6, 7
        , 7, 6, 4,  6, 5, 4,  4, 5, 0,  5, 1, 0
        , 0, 3, 4,  3, 7, 4,  1, 5, 2,  5, 6, 2];

    ///
    static private @trusted nothrow
    Vector3!PRECISION[] _transformedVertex(in ref Matrix4!PRECISION mat)
    {
        static auto vs = new Vector3!PRECISION[VERTEX.length];
        foreach (i, v; VERTEX)
            vs[i] = mat * v;
        return vs;
    }

    /// 当らなかったら -1。
    static @trusted nothrow
    PRECISION hitDistance(in ref Matrix4!PRECISION mat
                         , in ref Arrow!PRECISION arr)
    {
        auto vs = _transformedVertex(mat);
        HitState!PRECISION hs;
        for (size_t i = 0; i+3 <= INDEX_POLY.length; i+=3)
        {
            if (clockwise(arr.p, vs, INDEX_POLY[i..$])) continue;
            hs.crossState(arr, vs, INDEX_POLY[i..$]);
            if (hs.distance < PRECISION.max)
                return hs.distance;
            else
                hs.distance = PRECISION.max;
        }
        return -1;
    }

    /// 当たらなかったら -1。
    static @trusted
    PRECISION hitDistanceAve(in ref Matrix4!PRECISION mat
                            , in ref Arrow!PRECISION arr)
    {
        auto vs = _transformedVertex(mat);

        bool flag = false;
        HitState!PRECISION hs;
        for (size_t i = 0; i+3 <= INDEX_POLY.length; i+=3)
        {
            hs.crossState(arr, vs, INDEX_POLY[i..$]);
            if (hs.distance < PRECISION.max)
            { flag = true; break; }
        }

        return flag ? (Vector3!PRECISION(mat[12..15]) - arr.p).dot(arr.v) : -1;
    }
}
alias IdentityGeomf = IdentityGeom!float;





////////////////////XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\\\\\\\\\\\\\\\\\\\\
debug(matrix):

void main()
{
    version (unittest) writeln("unittest is well done.");
}
