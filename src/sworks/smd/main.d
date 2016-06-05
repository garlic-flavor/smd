/** Super Mars D-chan
 * Version:    0.0002(dmd2.071.0)
 * Date:       2016-Jun-06 02:50:35
 * License:    CC0
 * Authors:    KUMA

Macros:
  DMD_VERSION = 2.071.0

これは:
dmd と打ち間違えて smd と入力してしまった時に、スーパーマーズD言語ちゃんを出すウィンドウズデスクトップ用プログラムです。

謝辞:
$(UL
$(LI smd は D言語で書かれています。 $(LINK2 http://dlang.org/, Digital Mars D Programming Language))
$(LI 事の始まりは、 $(LINK http://echo.2ch.net/test/read.cgi/tech/1422155249/581) です。)
$(LI 元ネタは、$(LINK http://qiita.com/mattn/items/b7889e3c036b408ae8bd) です。)
$(LI 大元ネタは、$(LINK https://ja.wikipedia.org/wiki/Sl_(UNIX)) です。)
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
$(LI xxx)
)


履歴:
$(UL
$(LI 2016-06-05 ver.0.0002(dmd2.071.0) WS_EX_LAYERED使うように。)
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


int toMsecs(Duration d)
{
    int seconds, msecs;
    d.split!("seconds", "msecs")(seconds, msecs);
    return seconds * 1000 + msecs;
}


class SMD
{ mixin SingleWindowMix!() SWM;

    enum WIDTH = 256;
    enum d_chan = import("d-chan.svg").toCache.toSVG(WIDTH).toPolyLines;
    enum HEIGHT = cast(int)(d_chan.height);
    enum BG_COLOR = RGB(255, 255, 0);

    enum MIN_SIZE = 0.1f;
    enum MAX_SIZE = 3f;
    enum FADE_DURATION = 2000;

    BitmapDc bmp;
    SIZE size;
    HBRUSH bgBrush;

    POINT dPos;
    float dSize;

    this()
    {
        SWM.ready.regist;
        SWM.create(WS_POPUP, "SMD"w.ptr, Wnd(null), null, WS_EX_LAYERED);

        wnd.show(SW_SHOWMAXIMIZED | SW_HIDE);
        wnd.toTop;
        size = wnd.size;

        wnd.show;
    }

    LRESULT wm_create(Msg msg)
    {
        bgBrush = CreateSolidBrush(BG_COLOR);
        bmp = wnd.dc(d=>BitmapDc(d.ptr, rasterize(d_chan, d, bgBrush,
                                                  WIDTH, HEIGHT)));
        SetLayeredWindowAttributes(wnd.ptr, BG_COLOR, 0, LWA_COLORKEY);

        return 0;
    }

    LRESULT wm_destroy(Msg)
    {
        if (bgBrush) DeleteObject(bgBrush);
        bgBrush = null;
        bmp.clear;
        PostQuitMessage(0);
        return 0;
    }

    void wm_paint(Dc dc, ref PAINTSTRUCT ps)
    {
        dc.fill(ps.rcPaint, bgBrush);
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

            wnd.redraw;
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

    enum SPF = dur!"msecs"(33);
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
