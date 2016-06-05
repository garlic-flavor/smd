/** Super Mars D-chan
 * Version:    0.0001(dmd2.071.0)
 * Date:       2016-Jun-05 23:26:30
 * License:    CC0
 * Authors:    KUMA

Macros:
  DMD_VERSION = 2.071.0

これは:
dmd と打ち間違えて smd と入力してしまった時に、スーパーマーズD言語ちゃんを出すウィンドウズデスクトップ用プログラムです。

謝辞:
$(UL
$(LI smd は D言語で書かれています。 $(LINK2 http://dlang.org/, Digital Mars D Programming Language))
$(LI 事の始まりは、 $(LINK http://echo.2ch.net/test/read.cgi/tech/1422155249/581)です。)
$(LI 元ネタは、$(LINK http://qiita.com/mattn/items/b7889e3c036b408ae8bd)です。)
$(LI 大元ネタは、$(LINK https://ja.wikipedia.org/wiki/Sl_(UNIX))です。)
$(LI D言語ちゃんは、僕らのヒーローです。)
)

ビルド:
$(UL
$(LI -m32mscoff コンパイラオプションを利用します。VCのツールが使える状態にして下さい。)
)
$(PROMPT make release)

開発環境:
$(UL
$(LI Windows10 x64 + dmd2.071.0 + Visual Studio 2015)
)

ワナビー:
$(UL
$(LI WS_EX_LAYERED とかすっかり忘れてた。書き直そう。)
)


履歴:
$(UL
$(LI 2016-06-05 ver.0.0001(dmd2.071.0) とりあえず。)
)
 */
module sworks.smd.main;

version (README){}
else :

import sworks.base.matrix;
import sworks.util.cached_buffer;
import sworks.win32.util;
import sworks.win32.gdi;
import sworks.win32.single_window;
import sworks.win32.svgr;
import sworks.svg;
import core.time : Duration;
debug import std.stdio;

struct WindowContour
{
    POINT[] _points;
    INT[] _polyCounts;

    @property @nogc pure nothrow
    const(POINT)* pointPtr() const { return _points.ptr; }

    @property @nogc pure nothrow
    const(INT)* countPtr() const { return _polyCounts.ptr; }

    @property @nogc pure nothrow
    size_t count() const { return _polyCounts.length; }

    this(POINT[][] src)
    {
        import std.array : join;
        _points = src.join;
        _polyCounts = new INT[src.length];
        for (size_t i = 0; i < src.length; ++i)
            _polyCounts[i] = cast(INT)src[i].length;
    }

    WindowContour sameCapacityContour() const
    {
        WindowContour wc;
        wc._points = new POINT[_points.length];
        wc._polyCounts = _polyCounts.dup;
        return wc;
    }

    bool isSameCapacity(in ref WindowContour dst) const
    {
        return _points.length == dst._points.length &&
            _polyCounts == dst._polyCounts;
    }


    void stretchedCopy(ref WindowContour dst, int x, int y, float r)
    {
        assert(isSameCapacity(dst));
        for (size_t i = 0; i < _points.length; ++i)
        {
            dst._points[i] = POINT(cast(int)(x + _points[i].x * r),
                                   cast(int)(y + _points[i].y * r));
        }
    }

}


POINT[] jaggyLine(Vector2f a, Vector2f b)
{
    import std.math : floor, abs, ceil;
    int x1 = cast(int)a.x.floor;
    int y1 = cast(int)a.y.ceil;
    int x2 = cast(int)b.x.floor;
    int y2 = cast(int)b.y.ceil;
    int count = (x2 - x1).abs;
    if (0 == count) return [POINT(x1, y1), POINT(x2, y2)];

    int deltaX = (x2 - x1) / count;
    float deltaY = (cast(float)(y2 - y1)) / (cast(float)count);

    auto r = new POINT[count*2+1];
    r[0] = POINT(x1, y1);

    for ( int i = 0; i < count; ++i)
    {
        int y = y1 + cast(int)(deltaY * (i+1)).ceil;
        int x = x1 + deltaX * (i+1);

        r[i*2+1] = POINT(x, r[i*2].y);
        r[i*2+2] = POINT(x, y);
    }
    return r;
}

POINT[] jaggyLine(Vector2f[] poly)
{
    import std.array : Appender;
    Appender!(POINT[]) app;
    for (size_t i = 1; i < poly.length; ++i)
        app.put(jaggyLine(poly[i-1], poly[i]));
    return app.data;
}

int toMsecs(Duration d)
{
    int seconds, msecs;
    d.split!("seconds", "msecs")(seconds, msecs);
    return seconds * 1000 + msecs;
}


class SMD
{ mixin SingleWindowMix!() SWM;
    import core.time : seconds;

    enum WIDTH = 64;
    enum d_chan = import("d-chan.svg").toCache.toSVG(WIDTH).toPolyLines;
    enum HEIGHT = cast(int)(d_chan.height);

    enum MIN_SIZE = 0.5f;
    enum MAX_SIZE = 10f;
    enum FADE_DURATION = 2000;

    WindowContour src, resized;
    BitmapDc bmp;
    SIZE size;

    POINT dPos;
    float dSize;

    this()
    {
        SWM.ready.regist;
        SWM.create(WS_POPUP, "SMD"w.ptr);

        wnd.show(SW_SHOWMAXIMIZED | SW_HIDE);
        wnd.toTop;
        size = wnd.size;

        bmp = wnd.dc(d=>BitmapDc(d.ptr, rasterize!"black"(d_chan, d, WIDTH,
                                                          HEIGHT)));
        POINT[][] contourSrc;
        foreach (lines; d_chan.lines)
        {
            if (lines.haveClass("contour"))
            {
                foreach (poly; lines.pos)
                    contourSrc ~= poly.jaggyLine;
            }
        }
        src = WindowContour(contourSrc);
        resized = src.sameCapacityContour;

        wnd.show;
    }

    LRESULT wm_destroy(Msg)
    {
        bmp.clear;
        PostQuitMessage(0);
        return 0;
    }

    void wm_paint(Dc dc, ref PAINTSTRUCT ps)
    {
        dc.fill!"white"(ps.rcPaint);
        auto rc = RECT(dPos.x, dPos.y,
                       cast(int)(dPos.x + WIDTH * dSize),
                       cast(int)(dPos.y + HEIGHT * dSize));
        bmp.stretchTo(dc, rc);
    }


    import core.time : Duration;
    void update(Duration past)
    {
        void _update(int cx, int cy, float s)
        {
            dSize = s;
            auto w2 = cast(int)(WIDTH * s) / 2;
            auto h2 = cast(int)(HEIGHT * s) / 2;
            dPos = POINT(cx - w2, cy - h2);

            src.stretchedCopy(resized, dPos.x, dPos.y, dSize);
            auto rgn = CreatePolyPolygonRgn(resized.pointPtr, resized.countPtr,
                                            cast(int)resized.count, ALTERNATE);
            SetWindowRgn(wnd.ptr, rgn, false);
            wnd.redraw;
            DeleteObject(rgn);
        }

        auto pastms = past.toMsecs;
        if      (pastms < FADE_DURATION)
        {
            auto r = (cast(float)(pastms)) / (cast(float)(FADE_DURATION));
            _update(cast(int)(size.cx/2 * r), cast(int)(size.cy/2 * r),
                    MIN_SIZE + ((MAX_SIZE - MIN_SIZE) * r));
        }
        else if (pastms < FADE_DURATION * 2)
        {
            auto r = (cast(float)(pastms - FADE_DURATION))
                / (cast(float)(FADE_DURATION));
            _update(cast(int)(size.cx/2 * (1 + r)),
                    cast(int)(size.cy/2 * (1 + r)),
                    MAX_SIZE - ((MAX_SIZE - MIN_SIZE) * r));
        }
        else wnd.clear;
    }
}

void main(string[] args)
{
    import core.time : dur;
    import std.datetime : Clock;
    import std.utf : toUTF16z;

    enum SPF = dur!"msecs"(100);
    try
    {
        auto smd = new SMD;
        MSG msg;
        auto start = Clock.currTime;
        auto next = start + SPF;
        int sleep;
        for (; msg.message != WM_QUIT;)
        {
            smd.update(next - start);
            while(PeekMessage(&msg, smd.wnd.ptr, 0, 0, PM_REMOVE))
                DispatchMessage(&msg);
            (next - Clock.currTime).split!"msecs"(sleep);
            if (0 < sleep) Sleep(sleep);
            next += SPF;
        }
    }
    catch (WinException w) okbox(w.toStringWz);
    catch (Throwable t) okbox(t.toString.toUTF16z);
}
