/** SVGなんちゃってラスタライザ Win32GDI実装。
 * Date:       2016-Jun-05 18:14:14
 * Authors:
 * License:
**/
module sworks.win32.svgr;

import sworks.base.matrix;
import sworks.xml;
import sworks.svg;
import sworks.win32.util;
import sworks.win32.gdi;
debug import std.stdio;
///
HBITMAP rasterize(string BG)(SVGPL pl, Dc dc, int w, int h, int sample = 1)
{
    auto ww = w * sample;
    auto hh = h * sample;

    auto src = BitmapDc(dc.ptr, ww, hh);
    src.fill!BG(0, 0, ww, hh);
    foreach (ref one; pl.lines)
        draw(src, one, 0, 0, ww, hh);

    if (sample == 1) return src.dumpClear;
    else
    {
        auto tdc = BitmapDc(dc.ptr, w, h);
        SetStretchBltMode(tdc.ptr, HALFTONE);
        StretchBlt(tdc.ptr, 0, 0, w, h, src.ptr, 0, 0, ww, hh, SRCCOPY);
        src.clear;
        return tdc.dumpClear;
    }
}

HBITMAP rasterizeAlpha(SVGPL pl, Dc dc, int w, int h, int sample = 1)
{
    auto ww = w * sample;
    auto hh = h * sample;

    auto src = BitmapDc(dc.ptr, ww, hh, 32);
    foreach (ref one; pl.lines)
        draw(src, one, 0, 0, ww, hh);
    if (1 < sample) src.ptr.alphaStretch(w, h);

    GdiFlush();
    return src.dumpClear;
}

struct ColorMask { HBITMAP color, mask; }
ColorMask rasterizeMask(SVGPL pl, Dc dc, int w, int h, int sample = 1,
                        bool invert = false)
{
    auto ww = w * sample;
    auto hh = h * sample;

    auto src = BitmapDc(dc.ptr, ww, hh, 32);
    foreach (ref one; pl.lines)
        draw(src, one, 0, 0, ww, hh);
    if (1 < sample) src.ptr.alphaStretch(w, h);

    GdiFlush();
    ColorMask cm;
    cm.mask = src.splitMask(invert);
    cm.color = src.dumpClear;

    return cm;
}


/** クリッピングとフィルタを適用して描く。ボカしがメチャ遅い。

Params:
  dc    = 描画先
  lines = 描画対象
  x, y  = 描画位置
  w, h  = バックバッファのサイズ。$(BR)
          lines を拡大縮小するわけではない。
          ボカシやアルファ合成の処理に一時画像を生成するが、その大きさを
          指定する。通常は絵の全体の大きさを指定してください。
**/
void draw(Dc dc, PolyLines lines, int x, int y, int w, int h)
{
    // クリッピングの適用
    if (0 < lines.clip.length)
    {
        BeginPath(dc.ptr);
        draw(dc, lines.clip, x, y);
        EndPath(dc.ptr);
        SelectClipPath(dc.ptr, RGN_COPY);
    }

    // クリッピング部分以外の処理
    if      (lines.filter is null)
        draw(dc, x, y, w, h, lines.fill, lines.stroke, lines.opacity,
             1, lines.pos);
    else if (auto gbf = cast(GaussianBlurFilter)lines.filter)
    {
        draw(dc, x, y, w, h, lines.fill, lines.stroke, lines.opacity,
             cast(int)gbf.stdDeviation * 2, lines.pos);
    }

    // クリッピング領域の後始末
    if (0 < lines.clip.length)
        SelectClipRgn(dc.ptr, null);
}

//==============================================================================
//
// privates
//
//==============================================================================
// ↓このへんを参考に。
// $(LINK2 Bitmap Functions, https://msdn.microsoft.com/en-us/library/windows/desktop/dd183385%28v=vs.85%29.aspx)private

// クリッピングを考慮せずに描画する。
private
void draw(Dc dc, int x, int y, int w, int h, AFill af, AStroke as, float o,
          int b, Vector2f[][] p)
{
    auto f = cast(Fill)af;
    auto s = cast(Stroke)as;

    // 何の効果もなく、描画できる場合。
    if      (f !is null && s !is null && 1.0 == o && b <= 0)
    {
        BeginPath(dc.ptr);
        draw(dc, p, x, y);
        EndPath(dc.ptr);
        draw(dc, s, f);
    }
    else // 何らかの効果が適用されている場合。
    {
        // 塗り潰し。
        if      ((cast(NoFill)af) !is null){}
        else if (f !is null && 1.0 == o && b <= 0)
        {
            // 塗り潰しに関して、そのまま描画できる場合。
            BeginPath(dc.ptr);
            draw(dc, p, x, y);
            EndPath(dc.ptr);
            draw(dc, null, f);
        }
        else if (f !is null)
        {
            // 半透明の塗り潰し。
            alphaBlit(dc.ptr, x, y, w, h, (dc)
            {
                fillMask(dc, w, h, p);
                auto tdc = BitmapDc(dc.ptr, w, h, 32);
                tdc.fill(x, y, w, h, f.color);
                tdc.blitTo(dc, 0, 0, w, h, SRCPAINT);
                tdc.clear;
                dc.blurImage(b);
            }, o);
        }
        else if (auto rf = cast(RadialGradient)af)
        {
            // 円形グラデーションの塗り潰し
            alphaBlit(dc.ptr, x, y, w, h, (dc)
            {
                fillMask(dc, w, h, p);
                auto tdc = BitmapDc(dc.ptr, w, h, 32);
                tdc.fillRadialGradient(w, h, rf);
                tdc.blitTo(dc, 0, 0, w, h, SRCPAINT);
                tdc.clear;
                dc.blurImage(b);
            }, o);
        }
        else if (auto lf = cast(LinearGradient)af)
        {
            // 線形グラデーションの塗り潰し。
            alphaBlit(dc.ptr, x, y, w, h, (dc)
            {
                fillMask(dc, w, h, p);
                auto tdc = BitmapDc(dc.ptr, w, h, 32);
                tdc.fillLinearGradient(w, h, lf);
                tdc.blitTo(dc, 0, 0, w, h, SRCPAINT);
                tdc.clear;
                dc.blurImage(b);
            }, o);
        }

        // 線画
        if      ((cast(NoStroke)as) !is null){}
        else if (s !is null && 1 == o && b <= 1 && s.width <= 1
               && 1 <= s.opacity)
        {
            // 輪郭にはなんの効果もない場合。
            BeginPath(dc.ptr);
            draw(dc, p, x, y);
            EndPath(dc.ptr);
            draw(dc, s, null);
        }
        else if (s !is null)
        {
            // 輪郭に何らかの効果が適用されている場合。
            alphaBlit(dc.ptr, 0, 0, w+1, h+1, (dc)
            {
                // 半透明の輪郭
                auto tdc = BitmapDc(dc.ptr, w+1, h+1, 32);
                strokeMask(dc, w+1, h+1, cast(int)s.width, p);
                tdc.fill(x, y, w+1, h+1, s.color);
                tdc.blitTo(dc, 0, 0, w+1, h+1, SRCPAINT);
                tdc.clear;
                dc.blurImage(b);
            }, o * s.opacity);
        }
    }
}

// dc にパスを出力する。
private
void draw(Dc dc, Vector2f[][] pos, int cx, int cy)
{
    foreach (one; pos)
    {
        if (0 < one.length)
            dc.move(cast(int)(cx + one[0].x),
                    cast(int)(cy + one[0].y));

        for (size_t i = 1; i < one.length; ++i)
            dc.line(cast(int)(cx + one[i].x),
                    cast(int)(cy + one[i].y));
    }
}

// dc に保存されてるパスを stroke と fill を使って描画する。
private
void draw(Dc dc, Stroke stroke, Fill fill)
{
    import std.algorithm : max;

    HANDLE b, p;
    if (fill) b = SelectObject(dc.ptr, CreateSolidBrush(fill.color));
    if (stroke)
        p = SelectObject(dc.ptr,
             CreatePen(PS_SOLID, max(1, cast(int)(stroke.width)),
                                  stroke.color));

    if      (fill && stroke) StrokeAndFillPath(dc.ptr);
    else if (fill) FillPath(dc.ptr);
    else if (stroke) StrokePath(dc.ptr);

    if (b !is null) DeleteObject(SelectObject(dc.ptr, b));
    if (p !is null) DeleteObject(SelectObject(dc.ptr, p));
}

//
private
void fillLinearGradient(Dc dc, int w, int h, LinearGradient lg)
{
    alias fillLG = sworks.win32.gdi.fillLinearGradient;
    assert(lg && 0 < lg.stops.length);

    POINT toP(Vector2!float v){ return POINT(cast(int)v.x, cast(int)v.y); }

    auto point1 = toP(lg.pos1);
    auto point2 = toP(lg.pos2);
    auto stops = new GradientStop[lg.stops.length];
    for (size_t i = 0; i < stops.length; ++i)
    {
        auto a = (cast(uint)(255f * (1-lg.stops[i].opacity))) << 24;
        stops[i] = GradientStop(lg.stops[i].offset, lg.stops[i].color | a);
    }

    fillLG(dc, 0, 0, w, h, point1, point2, stops);
}

//
private
void fillRadialGradient(Dc dc, int w, int h, RadialGradient rg)
{
    alias fillRG = sworks.win32.gdi.fillRadialGradient!36;
    POINT toP(Vector2!float v){ return POINT(cast(int)v.x, cast(int)v.y); }
    auto p1 = toP(rg.pos1);
    auto p2 = toP(rg.pos2);
    auto stops = new GradientStop[rg.stops.length];
    for (size_t i = 0; i < stops.length; ++i)
    {
        auto a = (cast(uint)(255f * (1-rg.stops[i].opacity))) << 24;
        stops[i] = GradientStop(rg.stops[i].offset, rg.stops[i].color | a);
    }
    fillRG(dc, 0, 0, w, h, p2, p1, cast(int)rg.radius, rg.matrix, stops);
}

//
private
void fillMask(Dc dc, int w, int h, Vector2f[][] pos)
{
    dc.fill!"WHITE"(0, 0, w, h);
    dc.selectBrush!"BLACK";
    BeginPath(dc.ptr);
    dc.draw(pos, 0, 0);
    EndPath(dc.ptr);
    FillPath(dc.ptr);
}

//
private
void strokeMask(Dc dc, int w, int h, int b, Vector2f[][] pos)
{
    import std.algorithm : max;

    dc.fill!"WHITE"(0, 0, w, h);
    auto p = SelectObject(dc.ptr, CreatePen(PS_SOLID, max(1, b), 0));
    BeginPath(dc.ptr);
    dc.draw(pos, 0, 0);
    EndPath(dc.ptr);
    StrokePath(dc.ptr);
    DeleteObject(SelectObject(dc.ptr, p));
}

// ボカし。遅い上に結構適当。見た目がちょい違うかも。
void blurImage(Dc dc, int W)
{
    import sworks.win32.gdi : blur = blurImage;
    if (1 < W)
    {
        GdiFlush();
        BITMAP bm; dc.getBITMAP(bm);
        blur(bm, W, 4); //<----------------------------------------------- 適当
    }
}


////////////////////XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\\\\\\\\\\\\\\\\\\\\
debug(svgr):

import sworks.win32.single_window;
import sworks.util.cached_buffer;

final class Test
{ mixin SingleWindowMix!() SWM;

    enum WIDTH = 500;
    enum HEIGHT = 500;
    enum SAMPLE = 2;
// SVGPL pls;
    enum pls = import("tab_imagelist.svg").toCache.toSVG(WIDTH * SAMPLE)
        .toPolyLines;
    // enum pls = import("drawing.svg").toCache.toSVG(WIDTH * SAMPLE).toPolyLines;
    BitmapDc bmp;
    HBITMAP mask;

    this()
    {
        SWM.ready.regist;
        SWM.create(WS_OVERLAPPEDWINDOW | WS_VISIBLE, "test"w.ptr);

        wnd.dc((dc)
        {
            // bmp = BitmapDc(dc.ptr, rasterizeAlpha(pls, dc, WIDTH, HEIGHT,
            //                                       SAMPLE));
            auto colmask = rasterizeMask(pls, dc, WIDTH, HEIGHT, SAMPLE);
            bmp = BitmapDc(dc.ptr, colmask.color);
            mask = colmask.mask;
        });
    }

    LRESULT wm_destroy(Msg)
    {
        bmp.clear;
        PostQuitMessage(0);
        return 0;
    }

    void wm_paint(Dc dc, ref PAINTSTRUCT ps)
    {
        int cx = 0, cy = 0;

        dc.fill!"128 0 128"(ps.rcPaint);

        MaskBlt(dc.ptr, 0, 0, WIDTH, HEIGHT, bmp.ptr, 0, 0, mask, 0, 0,
                MAKEROP4(SRCCOPY, SRCPAINT));
        // SetStretchBltMode(dc.ptr, HALFTONE);
        // bmp.stretchTo(dc, RECT(0, 0, 640, 160));
        // alphaBlit(dc.ptr, 0, 0, WIDTH, HEIGHT,(dc)
        // {
        //     bmp.blitTo(dc, 0, 0);
        // });
        // bmp.blitTo(dc, 0, 0);

        // foreach (ref one; pls.lines)
        //     dc.draw(one, cx, cy, cast(int)pls.width, cast(int)pls.height);
    }
}

void main()
{
    import std.math;

    import std.utf : toUTF16z;

    try
    {
        scope auto tw = new Test();

        for (MSG msg; 0 < GetMessage(&msg, null, 0, 0);)
            DispatchMessage(&msg);
    }
    catch (WinException t) okbox(t.toStringWz);
    catch (Throwable t) okbox(t.toString.toUTF16z);
}

//##############################################################################
// resources for DEBUGGING
// $LINK(http://www.w3.org/TR/SVG/struct.html#EmbeddedSVGExample)
enum svg1 =
q{
<?xml version="1.0" standalone="yes"?>
<parent xmlns="http://example.org"
        xmlns:svg="http://www.w3.org/2000/svg">
   <!-- parent contents here -->
   <svg:svg width="4cm" height="8cm" version="1.1">
      <svg:ellipse cx="2cm" cy="4cm" rx="2cm" ry="1cm" />
   </svg:svg>
   <!-- ... -->
</parent>
};


enum svg2 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="5cm" height="4cm" version="1.1"
     xmlns="http://www.w3.org/2000/svg">
  <desc>Four separate rectangles
  </desc>
    <rect stroke="red" x="0.5cm" y="0.5cm" width="2cm" height="1cm"/>
    <rect stroke="blue" x="0.5cm" y="2cm" width="1cm" height="1.5cm"/>
    <rect stroke="green" x="3cm" y="0.5cm" width="1.5cm" height="2cm"/>
    <rect x="3.5cm" y="3cm" width="1cm" height="0.5cm"/>

  <!-- Show outline of canvas using 'rect' element -->
  <rect x=".01cm" y=".01cm" width="4.98cm" height="3.98cm"
        fill="none" stroke="blue" stroke-width=".02cm" />

</svg>
EOS";

// $(LINK http://www.w3.org/TR/SVG/struct.html#GroupsOverview)
// $LINK(http://www.w3.org/TR/SVG/images/struct/grouping01.svg)
enum svg3 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg xmlns="http://www.w3.org/2000/svg"
     version="1.1" width="5cm" height="5cm">
  <desc>Two groups, each of two rectangles</desc>
  <g id="group1" fill="red">
    <rect x="1cm" y="1cm" width="1cm" height="1cm"/>
    <rect x="3cm" y="1cm" width="1cm" height="1cm"/>
  </g>
  <g id="group2" fill="blue">
    <rect x="1cm" y="3cm" width="1cm" height="1cm"/>
    <rect x="3cm" y="3cm" width="1cm" height="1cm"/>
  </g>

  <!-- Show outline of canvas using 'rect' element -->
  <rect x=".01cm" y=".01cm" width="4.98cm" height="4.98cm"
        fill="none" stroke="blue" stroke-width=".02cm"/>
</svg>
EOS";


// $(LINK http://www.w3.org/TR/SVG/struct.html#DefsElement)
// $(LINK http://www.w3.org/TR/SVG/images/struct/defs01.svg)
enum svg4 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="8cm" height="3cm"
     xmlns="http://www.w3.org/2000/svg" version="1.1">
  <desc>Local URI references within ancestor's 'defs' element.</desc>
  <defs>
    <linearGradient id="Gradient01">
      <stop offset="20%" stop-color="#39F" />
      <stop offset="90%" stop-color="#F3F" />
    </linearGradient>
  </defs>
  <rect x="1cm" y="1cm" width="6cm" height="1cm" 
        fill="url(#Gradient01)"  />

  <!-- Show outline of canvas using 'rect' element -->
  <rect x=".01cm" y=".01cm" width="7.98cm" height="2.98cm"
        fill="none" stroke="blue" stroke-width=".02cm" />

</svg>
EOS";

// $(LINK http://www.w3.org/TR/SVG/struct.html#UseElement)
// $(LINK http://www.w3.org/TR/SVG/images/struct/Use01.svg)
enum svg5 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="10cm" height="3cm" viewBox="0 0 100 30" version="1.1"
     xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <desc>Example Use01 - Simple case of 'use' on a 'rect'</desc>
  <defs>
    <rect id="MyRect" width="60" height="10"/>
  </defs>
  <rect x=".1" y=".1" width="99.8" height="29.8"
        fill="none" stroke="blue" stroke-width=".2" />
  <use x="20" y="10" xlink:href="#MyRect" />
</svg>
EOS";

// $(LINK http://www.w3.org/TR/SVG/struct.html#UseElement)
// $(LINK http://www.w3.org/TR/SVG/images/struct/Use02.svg)
enum svg6 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="10cm" height="3cm" viewBox="0 0 100 30" version="1.1"
     xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <desc>Example Use02 - 'use' on a 'symbol'</desc>
  <defs>
    <symbol id="MySymbol" viewBox="0 0 20 20">
      <desc>MySymbol - four rectangles in a grid</desc>
      <rect x="1" y="1" width="8" height="8"/>
      <rect x="11" y="1" width="8" height="8"/>
      <rect x="1" y="11" width="8" height="8"/>
      <rect x="11" y="11" width="8" height="8"/>
    </symbol>
  </defs>
  <rect x=".1" y=".1" width="99.8" height="29.8"
        fill="none" stroke="blue" stroke-width=".2" />
  <use x="45" y="10" width="10" height="10" 
       xlink:href="#MySymbol" />
</svg>
EOS";

// $(LINK http://www.w3.org/TR/SVG/struct.html#UseElement)
// $(LINK http://www.w3.org/TR/SVG/images/struct/Use03.svg)
enum svg7 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="10cm" height="3cm" viewBox="0 0 100 30" version="1.1"
     xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <desc>Example Use03 - 'use' with a 'transform' attribute</desc>
  <defs>
    <rect id="MyRect" x="0" y="0" width="60" height="10"/>
  </defs>
  <rect x=".1" y=".1" width="99.8" height="29.8"
        fill="none" stroke="blue" stroke-width=".2" />
  <use xlink:href="#MyRect"
       transform="translate(20,2.5) rotate(10)" />
</svg>
EOS";

enum svg8 =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="10cm" height="3cm" viewBox="0 0 100 30"
     xmlns="http://www.w3.org/2000/svg" version="1.1">
  <desc>Example Use03-GeneratedContent - 'use' with a 'transform' attribute</desc>

  <!-- 'defs' section left out -->

  <rect x=".1" y=".1" width="99.8" height="29.8"
        fill="none" stroke="blue" stroke-width=".2" />

  <!-- Start of generated content. Replaces 'use' -->
  <g transform="translate(20,2.5) rotate(10)">
    <rect x="0" y="0" width="60" height="10"/>
  </g>
  <!-- End of generated content -->

</svg>
EOS";


// Todo: implement this
// $(LINK http://www.w3.org/TR/SVG/struct.html#UseElement)
// $(LINK http://www.w3.org/TR/SVG/images/struct/Use04.svg)
enum svg_noi =
q"EOS
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="12cm" height="3cm" viewBox="0 0 1200 300" version="1.1"
     xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
  <desc>Example Use04 - 'use' with CSS styling</desc>
  <defs style=" /* rule 9 */ stroke-miterlimit: 10" >
    <path id="MyPath" d="M300 50 L900 50 L900 250 L300 250"
                     class="MyPathClass"
                     style=" /* rule 10 */ stroke-dasharray:300,100" />
  </defs>
  <style type="text/css">
    <![CDATA[
      /* rule 1 */ #MyUse { fill: blue }
      /* rule 2 */ #MyPath { stroke: red }
      /* rule 3 */ use { fill-opacity: .5 }
      /* rule 4 */ path { stroke-opacity: .5 }
      /* rule 5 */ .MyUseClass { stroke-linecap: round }
      /* rule 6 */ .MyPathClass { stroke-linejoin: bevel }
      /* rule 7 */ use > path { shape-rendering: optimizeQuality }
      /* rule 8 */ g > path { visibility: hidden }
]]>
  </style>

  <rect x="0" y="0" width="1200" height="300"
         style="fill:none; stroke:blue; stroke-width:3"/>
  <g style=" /* rule 11 */ stroke-width:40">
    <use id="MyUse" xlink:href="#MyPath" 
         class="MyUseClass"
         style="/* rule 12 */ stroke-dashoffset:50" />
  </g>
</svg>
EOS";
