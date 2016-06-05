/** util.d
 * Date:       2016-Jun-05 20:33:05
 * Authors:    KUMA
 * License:    CC0
 */
module sworks.win32.util;
public import sworks.win32.port;
debug import sworks.win32.dump, std.stdio;

//------------------------------------------------------------------------------
//
// Message Procedure 関連
//
//------------------------------------------------------------------------------
/** ユーザー定義ウィンドウに指示を出す。
WPARAM = 指示のタイプ。
LPARAM = それ以外の情報。
**/
enum uint WM_INSTRUCTION = WM_APP + 1;



//------------------------------------------------------------------------------
/** これから読み込もうとしているDLLがあるフォルダを指定する。

現在の実行ファイルがあるディレクトリからの相対パスでも可。
**/
void setDLLDir(string dir)
{
    import std.array : array;
    import std.utf : toUTF16z;
    import std.file : thisExePath;
    import std.path : isAbsolute, buildPath, asNormalizedPath, dirName;
    if (dir.isAbsolute)
        SetDllDirectoryW(dir.toUTF16z);
    else
        SetDllDirectoryW(thisExePath.dirName.buildPath(dir).asNormalizedPath
            .array.toUTF16z);
}


//------------------------------------------------------------------------------
//
// 構造体の初期化
//
//------------------------------------------------------------------------------
/** 構造体の第一引数が構造体サイズであるようなよくあるやつ向け。
Params:
  args = 構造体の第二以降の引数
**/
auto initSize(T, ARGS...)(ARGS args) if (is(T == struct))
{ return T(T.sizeof, args); }

//------------------------------------------------------------------------------
// 例外関連
//------------------------------------------------------------------------------
/// ワイド文字バージョンの例外
class WinException : Exception
{
    import std.conv : to;

    static private wstring getError()
    {
        uint errorCode = GetLastError();
        wchar* msgBuf;
        scope(exit) LocalFree(cast(HANDLE)msgBuf);
        auto wrote = FormatMessage(
            FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM
            | FORMAT_MESSAGE_IGNORE_INSERTS | 0xff,
             null, errorCode, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
             cast(LPTSTR)&msgBuf, 0, null);
        return msgBuf[0..wrote].to!wstring;
    }

    private const(wchar)* lpsz_msg;

    //--------------------------------------
    this(T = wstring)(T msg = T.init, string file = __FILE__,
                      size_t line = __LINE__)
    {
        import std.array : join;
        super(msg.to!string, file, line);
        lpsz_msg = [getError, "\n", super.toString.to!wstring, "\0"].join.ptr;
    }

    @property @trusted @nogc pure nothrow
    const(wchar)* toStringWz() const { return lpsz_msg; }
}

/// std.exception.enforce のワイド文字バージョン。
T enforceW(T, U = wstring)(T val, lazy U str = null,
                            string file = __FILE__, size_t line = __LINE__)
{
    if (!val) { throw new WinException(str, file, line); }
    return val;
}

/// std.exception.enforce の、FAILED で検知するバージョン
int ensuccess(T = wstring)(int val, lazy T str = null,
                             string file = __FILE__, size_t line = __LINE__)
{
    if (FAILED(val)) { throw new WinException(str, file, line); }
    return val;
}

//------------------------------------------------------------------------------
// WNDCLASS 関連
//------------------------------------------------------------------------------
///
void ready(DWORD BG = COLOR_APPWORKSPACE)
    (WNDCLASSEX* wc, const(wchar)* class_name, WNDPROC proc, HINSTANCE h = null)
{
    with (*wc)
    {
        cbSize = WNDCLASSEX.sizeof;
        style = CS_HREDRAW | CS_VREDRAW | CS_OWNDC;
        lpfnWndProc = proc;
        hInstance = null !is h ? h : GetModuleHandle(null) ;
        if (hIcon is null) hIcon = LoadIcon(null,IDI_WINLOGO);
        if (hCursor is null) hCursor = LoadCursor(null,IDC_ARROW);
        static if (0 < BG)
        {
            if (hbrBackground is null)
                hbrBackground = GetSysColorBrush(BG);
        }
        lpszClassName =  class_name;
    }
}

///
void checkSingle(const(WNDCLASSEX)* wc)
{
    import std.conv : to;
    import std.algorithm : until;
    enforceW(null is FindWindowEx(null, null, wc.lpszClassName, null),
             "WndClass : "w
              ~ wc.lpszClassName[0..MAX_PATH].until('\0').to!wstring
              ~ " is already exist.");
}

///
void regist(WNDCLASSEX* wc)
{
    import std.conv : to;
    import std.algorithm : until;
    if (wc is null) return;
    RegisterClassEx(wc).enforceW("fail to regist window class: "w
        ~ wc.lpszClassName[0..MAX_PATH].until('\0').to!wstring);
}

///
void unregist(WNDCLASSEX* wc)
{ UnregisterClass(wc.lpszClassName, wc.hInstance); }


//------------------------------------------------------------------------------
// Window handle
//------------------------------------------------------------------------------
/// opacue HWND
struct Wnd
{
    private HWND _payload;

    ///
    @trusted @nogc pure nothrow
    this(HWND h){ _payload = h; }

    ///
    BOOL clear()
    {
        scope(exit) _payload = null;
        return DestroyWindow(_payload);
    }

    /// なかみ
    @property @trusted @nogc pure nothrow
    auto ptr() inout { return _payload; }

    ///
    @property @trusted @nogc pure nothrow
    bool empty() const { return _payload is null; }

    ///
    @trusted @nogc pure nothrow
    bool opEquals(in Wnd r) const { return _payload is r._payload; }

    ///
    @property
    Wnd parent() const
    { return Wnd(GetAncestor(cast(HWND)_payload, GA_PARENT)); }

    ///
    Wnd parent(Wnd np) @property { return Wnd(SetParent(_payload, np.ptr)); }

    ///
    BOOL close() { return PostMessage(_payload, WM_CLOSE, 0, 0); }

    ///
    BOOL redraw(RECT* rect = null, bool IsErase = true)
    { return InvalidateRect(_payload, rect, IsErase); }

    ///
    void show(int f = SW_SHOW) { ShowWindow(_payload, f); }
    ///
    void hide() { ShowWindow(_payload, SW_HIDE); }
    ///
    bool visible() @property const
    { return TRUE == IsWindowVisible(cast(HWND)_payload); }

    //--------------------------------------------------------------------
    // メッセージ関連
    /// メッセージを送る。
    LRESULT send(uint msg, WPARAM wp = 0, LPARAM lp=0)
    { return SendMessage(_payload, msg, wp, lp);}
    /// ditto
    LRESULT send(T)(uint msg, WPARAM wp, T* lp)
    { return SendMessage(_payload, msg, wp, cast(LPARAM)cast(void*)lp); }
    /// ditto
    LRESULT send(Msg msg)
    { return SendMessage(_payload, msg.msg, msg.wp, msg.lp); }
    /// ditto
    BOOL post(uint msg, WPARAM wp = 0, LPARAM lp = 0)
    { return PostMessage(_payload, msg, wp, lp); }
    /// ditto
    BOOL post(Msg msg) { return PostMessage(_payload, msg.msg, msg.wp, msg.lp); }
    /// ditto
    BOOL post(T)(uint msg, WPARAM wp, T* lp)
    { return PostMessage(_payload, msg, wp, cast(LPARAM)cast(void*)lp); }

    //--------------------------------------------------------------------
    // サイズ関連
    ///
    SIZE size() @property const
    {
        RECT rc;
        GetWindowRect(cast(HWND)_payload, &rc);
        return SIZE(rc.right-rc.left, rc.bottom-rc.top);
    }

    ///
    SIZE clientSize() @property const
    {
        RECT rc;
        GetClientRect(cast(HWND)_payload, &rc);
        return SIZE(rc.right-rc.left, rc.bottom-rc.top);
    }

    ///
    SIZE borderSize() @property const
    {
        RECT r; GetWindowRect(cast(HWND)_payload, &r);
        RECT cr; GetClientRect(cast(HWND)_payload, &cr);
        return SIZE(r.right - r.left - cr.right + cr.left,
                    r.bottom - r.top - cr.bottom + cr.top);
    }

    ///
    RECT childRect(Wnd child)
    {
        RECT rc;
        GetWindowRect(child.ptr, &rc);
        ScreenToClient(_payload, cast(POINT*) &(rc.left));
        ScreenToClient(_payload, cast(POINT*) &(rc.right));
        return rc;
    }

    POINT childPos(Wnd child)
    {
        RECT rc;
        GetWindowRect(child.ptr, &rc);
        ScreenToClient(_payload, cast(POINT*)&rc.left);
        return *cast(POINT*)&rc.left;
    }


    ///
    POINT pos() @property const
    {
        RECT rc; GetWindowRect(cast(HWND)_payload, &rc);
        ScreenToClient(parent.ptr, cast(POINT*) &(rc.left));
        return POINT(rc.left, rc.top);
    }

    ///
    bool isOn(in POINT p) @property const
    {
        RECT rc; GetWindowRect(cast(HWND)_payload, &rc);
        return rc.left <= p.x && p.x <= rc.right
            && rc.top <= p.y && p.y <= rc.bottom;
    }

    //--------------------------------------------------------------------
    // 移動関連
    ///
    LRESULT move(int x, int y, int w, int h, bool repaint = false)
    {
        return MoveWindow(_payload, x, y, w, h, repaint);
    }

    ///
    LRESULT move(int x, int y, bool repaint = false)
    {
        return SetWindowPos(_payload, null, x, y, 0, 0,
             (repaint?SWP_DRAWFRAME:SWP_NOREDRAW)
                | SWP_NOSIZE | SWP_NOZORDER);
    }

    ///
    LRESULT resize(int w, int h, bool repaint = false)
    {
        return SetWindowPos(_payload, null, 0, 0, w, h,
             (repaint?SWP_DRAWFRAME:SWP_NOREDRAW)
                | SWP_NOMOVE | SWP_NOZORDER);
    }

    ///
    LRESULT toTop()
    {
        return SetWindowPos(_payload, HWND_TOP, 0, 0, 0, 0,
             SWP_DEFERERASE | SWP_NOMOVE | SWP_NOSIZE);
    }

    //--------------------------------------------------------------------
    /// タイトル
    LRESULT text(const(wchar)* str)
    {
        return SendMessageW(_payload, WM_SETTEXT, 0,
                            cast(LPARAM)(cast(void*)str));
    }
    /// ditto
    LRESULT text(wstring str)
    {
        import std.utf : toUTF16z;
        return SendMessageW(_payload, WM_SETTEXT, 0,
                            cast(LPARAM)(cast(void*)str.toUTF16z));
    }

    /// ditto
    wstring text() const
    {
        import std.exception : assumeUnique;
        auto buf = new wchar[SendMessage(cast(HWND)_payload,
                             WM_GETTEXTLENGTH, 0, 0) + 1];
        SendMessage(cast(HWND)_payload, WM_GETTEXT, buf.length,
                    cast(LPARAM)(cast(void*)(buf.ptr)));
        return buf[0..$-1].assumeUnique;
    }

    //--------------------------------------------------------------------
    /// スタイル
    struct Style
    {
        LONG _payload;
        alias _payload this;
        private HWND target;

        private this(HWND t)
        {
            target = t;
            _payload = GetWindowLong(target, GWL_STYLE);
        }

        ///
        LONG opAssign(LONG s)
        {
            _payload = s;
            SetWindowLong(target, GWL_STYLE, s);
            return s;
        }

        ///
        LONG opOpAssign(string OP)(LONG s)
        {
            mixin("_payload " ~ OP ~ "= s;");
            return SetWindowLong(target, GWL_STYLE, _payload);
        }
    }

    ///
    Style style() { return Style(_payload); }

    //--------------------------------------------------------------------
    /// ID
    @property
    int id() { return GetDlgCtrlID(_payload); }

    //--------------------------------------------------------------------
    // ユーザーデータ関連
    //--------------------------------------------------------------------
    ///
    T* userdata(T : T*)()
    { return cast(T*)cast(void*)GetWindowLongPtr(_payload, GWL_USERDATA); }
    ///
    void userdata(T)(T data)
    { SetWindowLongPtr(_payload, GWL_USERDATA,
                       cast(LONG_PTR)cast(void*)data); }
    ///
    T userdata(T : LONG)()
    { return GetWindowLongPtr(_payload, GWL_USERDATA); }
    ///
    void userdata(T : LONG)(T i)
    { SetWindowLongPtr(_payload, GWL_USERDATA, i); }
}

//------------------------------------------------------------------------------
// メッセージ関連
//------------------------------------------------------------------------------
// for -m64
static if (4 == WPARAM.sizeof) alias SWPARAM = int;
else static if (8 == WPARAM.sizeof) alias SWPARAM = long;

static if (4 == LPARAM.sizeof) alias ULPARAM = uint;
else static if (8 == LPARAM.sizeof) alias ULPARAM = ulong;

/**
メッセージプロシジャでのメッセージの取り回しに。
**/
class Msg
{
    Wnd wnd; ///
    UINT msg; ///

    union
    {
        WPARAM wp; ///
        SWPARAM swp; ///
        struct
        {
            ushort lwp; ///
            ushort hwp; ///
            static if (8 == WPARAM.sizeof)
            {
                ushort hlwp; ///
                ushort hhwp; ///
            }
        }
        struct
        {
            short slwp; ///
            short shwp; ///
            static if (8 == WPARAM.sizeof)
            {
                short shlwp; ///
                short shhwp; ///
            }
        }
    }

    union
    {
        LPARAM lp; ///
        ULPARAM ulp; ///

        struct
        {
            ushort llp; ///
            ushort hlp; ///
            static if (8 == LPARAM.sizeof)
            {
                ushort hllp; ///
                ushort hhlp; ///
            }
        }
        struct
        {
            short sllp; ///
            short shlp; ///
            static if (8 == LPARAM.sizeof)
            {
                short shllp; ///
                short shhlp; //
            }
        }
    }
    bool preventDefault; ///

    ///
    @trusted @nogc pure nothrow
    this(HWND hWnd, UINT msg, WPARAM wp, LPARAM lp)
    {

        wnd = Wnd(hWnd);
        this.msg = msg;
        this.wp = wp;
        this.lp = lp;
        preventDefault = false;
    }

    ///
    nothrow
    LRESULT defProc()
    {return preventDefault ? 0 : DefWindowProc(wnd.ptr, msg, wp, lp); }

    ///
    @nogc pure nothrow
    T* pwp(T : T*)() @property { return cast(T*)wp; }
    ///
    @nogc pure nothrow
    T* plp(T : T*)() @property { return cast(T*)lp; }
    ///
    @trusted @nogc pure nothrow
    POINT point() { return POINT(sllp, shlp); }
}

/// T が、LRESULT wm_create(Msg) みたいな形をしてるか。
template IsMsgHandler(T)
{
    import std.traits : isCallable, ReturnType, ParameterTypeTuple;
    alias TYPE = ParameterTypeTuple!T;
    enum IsMsgHandler = isCallable!T && is(ReturnType!T : LRESULT)
                     && (1==TYPE.length) && is(TYPE[0] : Msg);
}

//------------------------------------------------------------------------------
// メッセージボックス関連
//------------------------------------------------------------------------------
///
nothrow
int okbox(const(wchar)* message, const(wchar)* caption = null,
          uint type = MB_OK)
{
    return MessageBox(null, message, caption, type);
}

/// ditto
nothrow
int okbox(const(wchar)[] message, const(wchar)[] caption = null,
          uint type = MB_OK)
{
    import std.utf : toUTF16z;
    return MessageBox(null, message.toUTF16z, caption.toUTF16z, type);
}

/// ditto
nothrow
int okbox(Wnd wnd, const(wchar)[] message, const(wchar)[] caption = "notice"w,
          uint type = MB_OK)
{
    import std.utf : toUTF16z;
    return MessageBoxW(wnd.ptr, message.toUTF16z, caption.toUTF16z, type);
}
/// ditto
nothrow
int okbox(Wnd wnd, const(wchar)* message, const(wchar)* caption = "notice",
          uint type = MB_OK)
{
    return MessageBoxW(wnd.ptr, message, caption, type);
}

//
nothrow
int yesnobox(Wnd wnd, const(wchar)* message, const(wchar)* caption = "prompt",
             uint type = MB_YESNO)
{
    return MessageBoxW(wnd.ptr, message, caption, type);
}

//------------------------------------------------------------------------------
// 右クリックで出すメニュー
//------------------------------------------------------------------------------

/// TrackPopupMenu のラッパ
class SubMenu
{
    protected HWND _menu;

    /// CreatePopupMenu で新しい空のメニューを作る。
    this(){ _menu = CreatePopupMenu(); }

    @trusted @nogc pure nothrow
    protected this(HWND m){ _menu = m; }

    ///
    void clear(){ DestroyMenu(_menu); _menu = null; }

    ///
    @trusted @nogc pure nothrow
    auto ptr() inout { return _menu; }

    ///
    bool append(const(wchar)[] name, uint id, uint upperOf = 0, uint state = 0)
    {
        auto mii = MENUITEMINFO(MENUITEMINFO.sizeof);
        with (mii)
        {
            fMask = MIIM_TYPE | MIIM_ID | (state ? MIIM_STATE : 0);
            fType = MFT_STRING;
            fState = state;
            wID = id;
            dwTypeData = cast(wchar*)name.ptr;
            cch = cast(UINT)name.length;
        }
        return 0 != InsertMenuItem(_menu, upperOf, false, &mii);
    }

    bool append(const(wchar)[] name, HMENU sub,
                uint upperOf = 0, uint state = 0)
    {
        auto mii = MENUITEMINFO(MENUITEMINFO.sizeof);
        with (mii)
        {
            fMask = MIIM_TYPE | MIIM_SUBMENU | (state ? MIIM_STATE : 0);
            fType = MFT_STRING;
            fState = state;
            hSubMenu = sub;
            dwTypeData = cast(wchar*)name.ptr;
            cch = cast(UINT)name.length;
        }
        return 0 != InsertMenuItem(_menu, upperOf, false, &mii);
    }

    bool appendSeparator(uint upperOf = 0)
    {
        auto mii = MENUITEMINFO(MENUITEMINFO.sizeof);
        mii.fMask = MIIM_FTYPE;
        mii.fType = MFT_SEPARATOR;
        return 0 != InsertMenuItem(_menu, upperOf, false, &mii);
    }

    /**
    Params:
       x, y = in client coordination of parent.
    **/
    bool start(HWND parent, int x, int y)
    {
        auto p = POINT(x, y);
        ClientToScreen(parent, &p);
        auto cx = GetSystemMetrics(SM_CXSCREEN);
        auto cy = GetSystemMetrics(SM_CYSCREEN);
        SetForegroundWindow(parent);
        return 0 != TrackPopupMenu(_menu,
             (cx/2 < p.x ? TPM_RIGHTALIGN : TPM_LEFTALIGN)
              | (cy/2 < p.y ? TPM_BOTTOMALIGN : TPM_TOPALIGN),
             p.x, p.y, 0, parent, null);
    }
}

//
class SubMenuFromResource : SubMenu
{
    HMENU _pMenu;
    /** LoadMenu によりリソースのニューを得る。
    Params:
      menuname = リソース名
      pos      = メニューアイテムの位置
    **/
    this(const(wchar)* menuname, int pos = 0, HANDLE hInst = null)
    {
        if (hInst is null) hInst = GetModuleHandle(null);
        _pMenu = LoadMenu(hInst, menuname);
        super(GetSubMenu(_pMenu, pos));
    }

    //
    override void clear()
    {
        DestroyMenu(_pMenu);
        _menu = null;
    }
}

/** XML をパースして右クリックメニューにする。

Description:
<menu> = ポップアップメニュー及び、そのサブメニューを作る。
  o 必須属性
    name = 文字列を指定する。
           サブメニューの表示名として使われる。
           start関数テンプレートの引数に指定してメニューを特定する。
           ' '(半角スペース)を含めることができる。
  o その他の属性
    base = 数値を指定する。
           以降のitem要素でid属性を指定しなかった場合、
           この数値を基準に、id の値を順次決定する。
  o 子要素
    <menu><item>

<item> = メニューのアイテム
  o その他の属性
    id   = 文字列を指定する。
           IDM.文字列 にushort型の参照値が登録される。
           WM_COMMAND に IDM.文字列の値が送られる。
    base = 数値を指定する。
           id の実際の値を指定する。
          この属性を指定しなかった場合は、直前の item の id 属性、
          もしくは base 属性の値+1 に設定される。
  o 必須子要素
    文字列 = メニューの表示名となる。
**/
mixin template SubMenuMix(string PATTERN)
{
    // サブメニューの ID と、初期化関数の定義
    mixin(
    {
        import sworks.xml;
        import std.conv : to;
        import std.string : join;
        import std.array : replace;

        auto _XML = PATTERN.toXMLs;
        string[] result = ["enum IDM:ushort{ _ZERO,"];

        int c, bc;
        foreach (axml; _XML)
        {
            if (auto one = cast(XML)axml)
            {
                if      (auto id = one.attr["id"])
                {
                        result ~= id;
                    if (auto base = one.attr["base"])
                        result ~= [" = ", base, ", "];
                    else
                        result ~= ", ";
                }
                else if ("item" == one.name)
                {
                    auto id = "_" ~ (c++).to!string;
                    result ~= [id, ", "];
                    one.attr["id"] = new StringValue(id);
                }

                if (auto base = one.attr["base"])
                    result ~= ["__", (bc++).to!string, " = ", base, ", "];
            }
        }
        result ~= "_LAST }";

        string _menuInit(AXML axml)
        {
            auto xml = cast(XML)axml;
            if (null is xml) return null;
            string[] buf;
            if      ("menu" == xml.name && "name" in xml.attr)
            {
                buf ~= "(SubMenu parent){ auto menu = new SubMenu;";
                foreach (one; xml.children)
                    buf ~= [_menuInit(one), "(menu);"];
                buf ~= ["if (parent !is null){",
                        "    parent.append(\"", xml.attr["name"],
                        "\", menu.ptr);",
                        "}",
                        "return menu; }"];
            }
            else if ("item" == xml.name && "id" in xml.attr)
            {
                buf ~= ["(SubMenu parent){ if (parent !is null){",
                        "    parent.append(\"", xml.searchText, "\"",
                        "                 , IDM.", xml.attr["id"], ");",
                        "} return null; }"];
            }
            return buf.join;
        }

        foreach (tag; _XML.children)
        {
            if (auto xml = cast(XML)tag)
            {
                if ("menu" == xml.name)
                {
                    if (auto pname = xml.attr["name"])
                    {
                        auto name = pname.replace(" ", "_");
                        result ~=["auto init_", name, " = ",
                                  _menuInit(xml), ";"];
                    }
                }
            }
        }

        return result.join;
    }());

    SubMenu[string] submenues;


    void clear()
    {
        foreach (one; submenues) one.clear;
        submenues = null;
    }

    ///
    bool start(string name)(HWND parent, int x, int y)
    {
        import std.array : replace;
        enum n = name.replace(" ", "_");
        if (auto psm = n in submenues) return (*psm).start(parent, x, y);
        else
        {
            auto m = mixin("init_" ~ n)(null);
            submenues[n] = m;
            return m.start(parent, x, y);
        }
        assert(0);
    }
}


//------------------------------------------------------------------------------
// スクロールバー関連
//------------------------------------------------------------------------------

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
// sugers
/// ウィンドウをスクロールする。
void scroll(Wnd h, int dx, int dy, in RECT* rect = null, in RECT* clip = null)
{ ScrollWindow(h.ptr, dx, dy, rect, clip); }

/// 画面左(上)端が全体に対してどの位置にあるかを [0, 1) で返す。
float getPosRatio(in ref SCROLLINFO si)
{ return (cast(float)si.nPos) / (cast(float)(si.nMax - si.nMin)); }
/// ditto
void setPosRatio(ref SCROLLINFO si, float r)
{
    with (si)
    {
        nPos = (cast(int)((nMax - nMin) * r)) + nMin;
        if (nMax < nPos + nPage) nPos = nMax - nPage;
        if (nPos < nMin) nPos = nMin;
    }
}

/// SCROLLINFO 構造体のコンストラクタのシュガー
@trusted @nogc pure nothrow
SCROLLINFO newSCROLLINFO(int mask = SIF_RANGE | SIF_PAGE | SIF_POS)
{ return SCROLLINFO(SCROLLINFO.sizeof, mask); }

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// スクロールバーの諸元を一括設定
int TsetScrollInfo(int TYPE)(Wnd h, int min, int max, uint page, int pos,
                             bool repaint = false)
    if (TYPE == SB_CTL || TYPE == SB_HORZ || TYPE == SB_VERT)
{
    auto si = newSCROLLINFO;
    with (si)
    {
        nMin = min;
        nMax = max;
        nPage = page;
        nPos = pos;
    }
    return SetScrollInfo(h.ptr, TYPE, &si, repaint);
}
/// ditto
alias setScrollInfoH = TsetScrollInfo!SB_HORZ;
/// ditto
alias setScrollInfoV = TsetScrollInfo!SB_VERT;
/// ditto
alias setScrollInfo = TsetScrollInfo!SB_CTL;
/// 縦横のスクロールバーの情報を同時に設定。
void setScrollInfo(Wnd h, in RECT size, in SIZE page, in POINT pos,
                   bool repaint = false)
{
    auto si = newSCROLLINFO;
    with (si)
    {
        nMin = size.left;
        nMax = size.right;
        nPage = page.cx;
        nPos = pos.x;
    }
    SetScrollInfo(h.ptr, SB_HORZ, &si, repaint);
    with (si)
    {
        nMin = size.top;
        nMax = size.bottom;
        nPage = page.cy;
        nPos = pos.y;
    }
    SetScrollInfo(h.ptr, SB_VERT, &si, repaint);
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/** スクロールバーのレンジとページサイズを変更。
Returns:
  変更前とおよそ同じ位置の新しい位置。
**/
int setScrollInfo2(int type)(Wnd h, int min, int max, int page,
                             bool repaint = false)
{
    auto si = newSCROLLINFO;
    GetScrollInfo(h.ptr, type, &si);
    auto r = si.getPosRatio;
    with (si)
    {
        fMask |= SIF_PAGE;
        nMin = min;
        nMax = max;
        nPage = page;
    }
    si.setPosRatio(r);
    SetScrollInfo(h.ptr, type, &si, repaint);
    return si.nPos;
}
/// ditto
alias setScrollInfoV = setScrollInfo2!SB_VERT;
/// ditto
alias setScrollInfoH = setScrollInfo2!SB_HORZ;
/// ditto
alias setScrollInfo = setScrollInfo2!SB_CTL;
/// 縦と横を同時に設定
POINT setScrollInfo(Wnd h, in RECT range, in SIZE page, bool repaint = false)
{
    auto si = newSCROLLINFO;
    POINT ret;
    void _set(int type, int nmin, int nmax, int npage)
    {
        GetScrollInfo(h.ptr, type, &si);
        auto r = si.getPosRatio;
        with (si)
        {
            nMin = nmin;
            nMax = nmax;
            nPage = npage;
        }
        si.setPosRatio(r);
        SetScrollInfo(h.ptr, type, &si, repaint);
    }
    _set(SB_HORZ, range.left, range.right, page.cx);
    ret.x = si.nPos;
    _set(SB_VERT, range.top, range.bottom, page.cy);
    ret.y = si.nPos;
    return ret;
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// スクロールバーのページサイズのみ設定
int TsetScrollPage(int TYPE)(Wnd h, uint page, bool repaint = false)
    if (TYPE == SB_HORZ || TYPE == SB_VERT || TYPE == SB_CTL)
{
    auto si = newSCROLLINFO;
    GetScrollInfo(h.ptr, TYPE, &si);
    auto r = si.getPosRatio;
    si.fMask = SIF_POS | SIF_PAGE;
    si.nPage = page;
    si.setPosRatio(r);
    SetScrollInfo(h.ptr, TYPE, &si, repaint);
    return si.nPos;
}
/// ditto
alias setScrollPageH = TsetScrollPage!SB_HORZ;
/// ditto
alias setScrollPageV = TsetScrollPage!SB_VERT;
/// ditto
alias setScrollPage = TsetScrollPage!SB_CTL;
/// 縦と横とを同時に設定。
POINT setScrollPage(Wnd h, SIZE page, bool repaint = false)
{
    auto si = newSCROLLINFO;
    POINT ret;
    void _set(int type, int npage)
    {
        si.fMask = SIF_POS | SIF_RANGE | SIF_PAGE;
        GetScrollInfo(h.ptr, type, &si);
        auto r = si.getPosRatio;
        si.fMask = SIF_PAGE | SIF_POS;
        si.nPage = page.cx;
        si.setPosRatio(r);
        SetScrollInfo(h.ptr, type, &si, repaint);
    }
    _set(SB_HORZ, page.cx);
    ret.x = si.nPos;
    _set(SB_VERT, page.cy);
    ret.y = si.nPos;
    return ret;
}


//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// ゲッタのシュガー
SCROLLINFO TgetScrollInfo(int TYPE)
    (Wnd h, uint mask = SIF_RANGE | SIF_PAGE | SIF_POS)
        if (TYPE == SB_CTL || TYPE == SB_HORZ || TYPE == SB_VERT)
{
    auto si = newSCROLLINFO(mask);
    GetScrollInfo(h.ptr, TYPE, &si);
    return si;
}
/// ditto
alias getScrollInfoH = TgetScrollInfo!SB_HORZ;
/// ditto
alias getScrollInfoV = TgetScrollInfo!SB_VERT;
/// ditto
alias getScrollInfo = TgetScrollInfo!SB_CTL;

/// 位置を取得するシュガー
int TgetScrollPos(int TYPE)(in Wnd h)
    if (TYPE == SB_CTL || TYPE == SB_HORZ || TYPE == SB_VERT)
{
    auto si = newSCROLLINFO(SIF_POS);
    GetScrollInfo(cast(HWND)h.ptr, TYPE, &si);
    return si.nPos;
}
/// ditto
alias getScrollPosH = TgetScrollPos!SB_HORZ;
/// ditto
alias getScrollPosV = TgetScrollPos!SB_VERT;
/// ditto
alias getScrollPos = TgetScrollPos!SB_CTL;

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// 位置セッタのシュガー。
int TsetScrollPos(int TYPE)(Wnd h, int pos, bool repaint = false)
{
    auto si = newSCROLLINFO(SIF_POS);
    si.nPos = pos;
    return SetScrollInfo(h.ptr, TYPE, &si, repaint);
}
/// ditto
alias setScrollPosH = TsetScrollPos!SB_HORZ;
/// ditto
alias setScrollPosV = TsetScrollPos!SB_VERT;
/// ditto
alias setScrollPos = TsetScrollPos!SB_CTL;

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/** レンジ設定

Notes:
  ページサイズはレンジの範囲を越えないようにWin32側が切り詰めるので
  レンジと一緒にページも設定する必要がある。

Returns:
  新しい位置
**/
int TsetScrollRange(int TYPE)(Wnd h, int min, int max, int page,
                              bool repaint = false)
    if (TYPE == SB_CTL || TYPE == SB_HORZ || TYPE == SB_VERT)
{
    auto si = newSCROLLINFO(SIF_POS);
    GetScrollInfo(h.ptr, TYPE, &si);
    with (si)
    {
        fMask = SIF_POS | SIF_RANGE | SIF_PAGE;
        nMin = min;
        nMax = max;
        nPage = page;
        if (nMax < nPos + page) nPos = max - page;
        if (nPos < min) nPos = min;
    }
    SetScrollInfo(h.ptr, TYPE, &si, repaint);
    return si.nPos;
}
/// ditto
alias setScrollRangeH = TsetScrollRange!SB_HORZ;
/// ditto
alias setScrollRangeV = TsetScrollRange!SB_VERT;
/// ditto
alias setScrollRange = TsetScrollRange!SB_CTL;
/// ditto
POINT setScrollRange(Wnd h, in RECT range, bool repaint = false)
{
    auto si = SCROLLINFO(SCROLLINFO.sizeof);
    POINT ret;
    void _set(int type, int nmin, int nmax)
    {
        si.fMask = SIF_POS | SIF_PAGE;
        GetScrollInfo(h.ptr, type, &si);
        with (si)
        {
            nMin = nmin;
            nMax = nmax;
            if (nMax < nPos + nPage) nPos = nMax - nPage;
            if (nPos < nMin) nPos = nMin;
        }
        SetScrollInfo(h.ptr, type, &si, repaint);
    }
    _set(SB_HORZ, range.left, range.right);
    ret.x = si.nPos;
    _set(SB_VERT, range.top, range.bottom);
    ret.y = si.nPos;
    return ret;
}

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/** ウィンドウメッセージをよくある感じに処理。
Returns:
  スクロールすべき差
**/
int TvalidateScrollDelta(int TYPE)(Msg msg, int STEP = 10)
{
    auto si = newSCROLLINFO;
    GetScrollInfo(msg.wnd.ptr, TYPE, &si);
    int delta = 0;
    switch(msg.lwp)
    {
        case        SB_LINEDOWN:      delta = STEP;
        break; case SB_LINEUP:        delta = -STEP;
        break; case SB_PAGEDOWN:      delta = si.nPage;
        break; case SB_PAGEUP:        delta = -si.nPage;
        break; case SB_THUMBPOSITION:
        case        SB_THUMBTRACK:    delta = (msg.shwp - si.nPos);
        break; default:
    }

    auto np = si.nPos + delta;
    if (si.nMax < np + si.nPage) np = si.nMax - si.nPage;
    if (np < si.nMin) np = si.nMin;

    delta = np - si.nPos;
    if (delta != 0)
    {
        with (si)
        {
            fMask = SIF_POS;
            nPos = np;
        }
        SetScrollInfo(msg.wnd.ptr, TYPE, &si, true);
    }
    return delta;
}
/// ditto
alias validateScrollDeltaH = TvalidateScrollDelta!SB_HORZ;
/// ditto
alias validateScrollDeltaV = TvalidateScrollDelta!SB_VERT;
/// ditto
alias validateScrollDelta = TvalidateScrollDelta!SB_CTL;

//++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
/// ウィンドウをよくある感じにスクロールするプロシジャチェイン
void scrollChain(int STYLE)(Msg msg, ref Object param)
{
    msg.preventDefault = true;
    switch(msg.msg)
    {
        case        WM_VSCROLL:
            if (auto delta = msg.validateScrollDeltaV)
                msg.wnd.scroll(0, -delta);
        break; case WM_HSCROLL:
            if (auto delta = msg.validateScrollDeltaH)
                msg.wnd.scroll(-delta, 0);
        break; case WM_MOUSEWHEEL:
            static if (STYLE == WS_HSCROLL)
            {
                auto delta = msg.shwp;
                if      (0 < delta) msg.wnd.send(WM_HSCROLL, SB_LINEUP);
                else if (delta < 0) msg.wnd.send(WM_HSCROLL, SB_LINEDOWN);
            }
            else
            {
                auto delta = msg.shwp;
                if      (delta < 0) msg.wnd.send(WM_VSCROLL, SB_LINEUP);
                else if (0 < delta) msg.wnd.send(WM_VSCROLL, SB_LINEDOWN);
            }
        break; case WM_MOUSEHWHEEL:
            auto delta = msg.shwp;
            if      (0 < delta) msg.wnd.send(WM_HSCROLL, SB_LINEUP);
            else if (delta < 0) msg.wnd.send(WM_HSCROLL, SB_LINEDOWN);
        break; case WM_SIZE:
            static if      (STYLE == WS_HSCROLL)
                setScrollPageH(msg.wnd, msg.llp);
            else static if (STYLE == WS_VSCROLL)
                setScrollPageV(msg.wnd, msg.hlp);
            else static if (STYLE & WS_HSCROLL && STYLE & WS_VSCROLL)
                setScrollPage(msg.wnd, SIZE(msg.llp, msg.hlp));
        break; default:
            msg.preventDefault = false;
    }
}

//------------------------------------------------------------------------------
// プロシジャチェイン
//------------------------------------------------------------------------------
/** WM_MOUSEHOVER、WM_MOUSELEAVE 及び BN_CLICKED を受け取れるようになる。
5ピクセル以内、GetDoubleClickTime() 以内にボタンを押して、上げたら
  -> BN_CLICKED
**/
void trackMouseChain(Msg msg, ref Object param)
{
    import std.math : abs;

    class P
    { bool hoverNow; POINT downPos; DWORD downTime; }

    if (param is null) param = new P;
    auto p = cast(P)param;
    switch(msg.msg)
    {
        case        WM_LBUTTONDOWN:
            p.downPos = POINT(msg.sllp, msg.shlp);
            p.downTime = GetTickCount();
        break; case WM_LBUTTONUP:
            if (abs(msg.sllp - p.downPos.x) + abs(msg.shlp - p.downPos.y) < 5
              && GetTickCount() < p.downTime + GetDoubleClickTime())
                msg.wnd.post(WM_COMMAND, MAKEWPARAM(0, BN_CLICKED), msg.lp);
        break; case WM_MOUSEMOVE:
            if (!p.hoverNow)
            {
                p.hoverNow = true;
                TRACKMOUSEEVENT tme;
                with (tme)
                {
                    cbSize = TRACKMOUSEEVENT.sizeof;
                    dwFlags = TME_HOVER | TME_LEAVE;
                    hwndTrack = msg.wnd.ptr;
                    dwHoverTime = HOVER_DEFAULT;
                }
                TrackMouseEvent(&tme);
            }
        break; case WM_MOUSEHOVER: case WM_MOUSELEAVE:
            p.hoverNow = false;
        break; default:
    }
}

///
struct NMHOVER
{
    NMHDR hdr;
    wstring tooltip;
}

///
void trackMouseHoverChain(Msg msg, ref Object param)
{
    import core.sys.windows.commctrl : NM_HOVER;
    import std.math : abs;

    class P
    { bool hoverNow; }

    if (param is null) param = new P;
    auto p = cast(P)param;
    switch(msg.msg)
    {
        case WM_MOUSEMOVE:
            if (!p.hoverNow)
            {
                p.hoverNow = true;
                TRACKMOUSEEVENT tme;
                with (tme)
                {
                    cbSize = TRACKMOUSEEVENT.sizeof;
                    dwFlags = TME_HOVER | TME_LEAVE;
                    hwndTrack = msg.wnd.ptr;
                    dwHoverTime = HOVER_DEFAULT;
                }
                TrackMouseEvent(&tme);
            }
        break; case WM_MOUSEHOVER: case WM_MOUSELEAVE:
            p.hoverNow = false;
        break; default:
    }
}


//------------------------------------------------------------------------------
//
mixin template HoverTooltipMix(alias wnd, alias id)
{
    static assert(is(typeof(wnd) : Wnd) && is(typeof(id) : ushort));

    wstring tooltip;
    LRESULT wm_mousehover(Msg msg)
    {
        import core.sys.windows.commctrl : NM_HOVER;
        auto nm = NMHOVER(NMHDR(wnd.ptr, id, NM_HOVER), tooltip);
        wnd.parent.send(WM_NOTIFY, id, &nm);
        return msg.defProc;
    }

    LRESULT wm_mouseleave(Msg msg)
    {
        auto nm = NMHDR(wnd.ptr, id, WM_MOUSELEAVE);
        wnd.parent.send(WM_NOTIFY, id, &nm);
        return msg.defProc;
    }
}

//------------------------------------------------------------------------------
// 文字列関連
//------------------------------------------------------------------------------
///
SIZE calcTextSize(Wnd wnd, const(wchar)[] str, HFONT f = null)
{
    SIZE size;
    auto hdc = GetDC(wnd.ptr);
    if (f !is null) f = SelectObject(hdc, f);
    GetTextExtentPoint32W(hdc, str.ptr, cast(int)str.length, &size);
    if (f !is null) f = SelectObject(hdc, f);
    ReleaseDC(wnd.ptr, hdc);
    return size;
}

///
SIZE calcTextSize(Wnd wnd, const(wchar)* str, HFONT f = null)
{
    SIZE size;
    auto hdc = GetDC(wnd.ptr);
    int length;
    for (; str[length] != '\0' ; ++length){}
    if (f !is null) f = SelectObject(hdc, f);
    GetTextExtentPoint32W(hdc, str, length, &size);
    if (f !is null) f = SelectObject(hdc, f);
    ReleaseDC(wnd.ptr, hdc);
    return size;
}

//------------------------------------------------------------------------------
// CreateWindow
//------------------------------------------------------------------------------
/**
単なるエジットボックスとか、ボタンとかプロシジャ使わないような簡易な
ウィンドウ用
**/
Wnd Create(const(wchar)* class_name, uint style, uint exStyle,
           Wnd parent = Wnd(null), const(wchar)* title = null,
           int x = CW_USEDEFAULT, int y = CW_USEDEFAULT,
           int w = CW_USEDEFAULT, int h = CW_USEDEFAULT,
           HMENU menu = null, HINSTANCE hInst = null)
{
    import std.conv : to;
    import std.algorithm : until;
    if (hInst is null) hInst = GetModuleHandle(null);
    return Wnd(CreateWindowEx(exStyle, class_name, title, style, x, y, w, h,
                              parent.ptr, menu, hInst, null).
        enforceW("fail at CreateWindowEx("w
                ~ class_name[0..MAX_PATH].until('\0').to!wstring ~")."w));
}
/// コントロール用。menu が ushort 型で、コントロールID を取る。
Wnd Create(const(wchar)* class_name, uint style, uint exStyle, Wnd parent,
           ushort menu, const(wchar)* title = null,
           int x = CW_USEDEFAULT, int y = CW_USEDEFAULT,
           int w = CW_USEDEFAULT, int h = CW_USEDEFAULT,
           HINSTANCE hInst = null)
{
    import std.conv : to;
    import std.algorithm : until;
    if (hInst is null) hInst = GetModuleHandle(null);
    return Wnd(CreateWindowEx(exStyle, class_name, title, style, x, y, w, h,
                              parent.ptr, cast(HMENU)menu, hInst, null)
        .enforceW("fail at CreateWindowEx("w
                 ~ class_name[0..MAX_PATH].until('\0').to!wstring ~")."w));
}


//------------------------------------------------------------------------------
// その他
//------------------------------------------------------------------------------

///
void setClientSize(Wnd wnd, int width, int height, bool repaint=true)
{
    RECT crc; GetClientRect(wnd.ptr, &crc);
    int dx = width-crc.right+crc.left;
    int dy = height-crc.bottom+crc.top;
    RECT wrc; GetWindowRect(wnd.ptr, &wrc);
    SetWindowPos(wnd.ptr, null, 0, 0, wrc.right-wrc.left+dx,
                 wrc.bottom-wrc.top+dy,
                 (repaint ? SWP_DEFERERASE : SWP_NOREDRAW)
                  | SWP_NOMOVE | SWP_NOZORDER);
}

// マウスリーブを得る。
void trackMouseLeave(Wnd wnd)
{
    TRACKMOUSEEVENT tme;
    with (tme)
    {
        cbSize = TRACKMOUSEEVENT.sizeof;
        dwFlags = TME_LEAVE;
        hwndTrack = wnd.ptr;
    }
    TrackMouseEvent(&tme);
}
//
void trackMouseHover(Wnd wnd, uint timeout = HOVER_DEFAULT)
{
    TRACKMOUSEEVENT tme;
    with (tme)
    {
        cbSize = TRACKMOUSEEVENT.sizeof;
        dwFlags = TME_HOVER;
        hwndTrack = wnd.ptr;
        dwHoverTime = timeout;
    }
    TrackMouseEvent(&tme);
}

//
SIZE getIconSize(HICON icon)
{
    import std.exception : enforce;
    assert(icon);
    ICONINFO info; GetIconInfo(icon, &info).enforce;
    if      (auto bmp = info.hbmColor)
    {
        BITMAP b; GetObject(bmp, b.sizeof, &b);
        return SIZE(b.bmWidth, b.bmHeight);
    }
    else if (auto bmp = info.hbmMask)
    {
        BITMAP b; GetObject(bmp, b.sizeof, &b);
        return SIZE(b.bmWidth, b.bmHeight / 2);
    }
    else throw new Exception("not a valid icon.");
}

//------------------------------------------------------------------------------
// ディスクトレイ関連
//------------------------------------------------------------------------------
/// ディスクトレイを開く。
void ejectDisk(wstring drivename)
{
    import std.exception : enforce;
    import std.path : driveName;
    import core.sys.windows.winioctl;
    auto drivestr = drivename.driveName;
    enforce(0 < drivestr.length);
    auto name = "\\\\.\\"w ~ drivestr ~ "\0"w;
    auto handle = CreateFile(name.ptr, GENERIC_READ | GENERIC_WRITE,
                             FILE_SHARE_READ | FILE_SHARE_WRITE,
                             null, OPEN_EXISTING, 0, null);
    enforce(INVALID_HANDLE_VALUE != handle);
    scope(exit) CloseHandle(handle);
    DWORD bytes = 0;
    if (!isDiskTrayOpen(handle))
    {
        DeviceIoControl(handle, FSCTL_LOCK_VOLUME, null, 0, null, 0,
                        &bytes, null);
        DeviceIoControl(handle, FSCTL_DISMOUNT_VOLUME, null, 0, null, 0,
                        &bytes, null);
        DeviceIoControl(handle, IOCTL_STORAGE_EJECT_MEDIA, null, 0, null, 0,
                        &bytes, null);
    }
    else DeviceIoControl(handle, IOCTL_STORAGE_LOAD_MEDIA, null, 0, null, 0,
                         &bytes, null);
}

/// ディスクトレイが開いているかどうか。
bool isDiskTrayOpen(HANDLE hDevice)
{
    enum SCSI_IOCTL_DATA_OUT = 0;
    enum SCSI_IOCTL_DATA_IN  = 1;
    enum SCSI_IOCTL_DATA_UNSPECIFIED = 2;

    enum MAX_SENSE_LEN = 18;

    enum IOCTL_SCSI_PASS_THROUGH_DIRECT = 0x4D014;

    struct SCSI_PASS_THROUGH_DIRECT
    {
        USHORT Length;
        UCHAR ScsiStatus;
        UCHAR PathId;
        UCHAR TargetId;
        UCHAR Lun;
        UCHAR CdbLength;
        UCHAR SenseInfoLength;
        UCHAR DataIn;
        ULONG DataTransferLength;
        ULONG TimeOutValue;
        PVOID DataBuffer;
        ULONG SenseInfoOffset;
        UCHAR[16] Cdb;
    }

    struct SCSI_PASS_THROUGH_DIRECT_AND_SENSE_BUFFER
    {
        SCSI_PASS_THROUGH_DIRECT sptd;
        UCHAR[MAX_SENSE_LEN] SenseBuf;
    }

    SCSI_PASS_THROUGH_DIRECT_AND_SENSE_BUFFER sptd_sb;
    byte[8] dataBuf = 0;
    with (sptd_sb.sptd)
    {
        Length = SCSI_PASS_THROUGH_DIRECT.sizeof;
        PathId = 0;
        TargetId = 0;
        Lun = 0;
        CdbLength = 10;
        SenseInfoLength = MAX_SENSE_LEN;
        DataIn = SCSI_IOCTL_DATA_IN;
        DataTransferLength = dataBuf.length;
        TimeOutValue = 2;
        DataBuffer = dataBuf.ptr;
        SenseInfoOffset = SCSI_PASS_THROUGH_DIRECT.sizeof;
        Cdb = [0x4a, 1, 0, 0,
               0x10, 0, 0, 0,
               8, 0, 0, 0,
               0, 0, 0, 0];
    }
    sptd_sb.SenseBuf[] = 0;

    DWORD dwBytesReturned;
    DeviceIoControl(hDevice, IOCTL_SCSI_PASS_THROUGH_DIRECT, &sptd_sb,
                    sptd_sb.sizeof, &sptd_sb, sptd_sb.sizeof,
                    &dwBytesReturned, null);
    return dataBuf[5] == 1;
}


//------------------------------------------------------------------------------
/// リソース内のモノクロビットマップを読み込む。
HBITMAP loadMonoBitmap(Wnd wnd, const(wchar)* name, DWORD fgColor,
                       DWORD bgColor)
{
    import std.exception : enforce;
    auto monoBmp = LoadImage(GetModuleHandle(null), name, IMAGE_BITMAP, 0, 0,
                             LR_DEFAULTSIZE | LR_CREATEDIBSECTION).enforceW;
    BITMAP bmp;
    GetObject(monoBmp, bmp.sizeof, &bmp);
    enforce(bmp.bmBitsPixel == 1);
    auto hdc = GetDC(wnd.ptr);
    auto hcdc = CreateCompatibleDC(hdc);
    ReleaseDC(wnd.ptr, hdc);
    auto oldbmp = SelectObject(hcdc, monoBmp);
    SetDIBColorTable(hcdc, 0, 2, cast(RGBQUAD*)[bgColor, fgColor].ptr);
    SelectObject(hcdc, oldbmp);
    ReleaseDC(wnd.ptr, hcdc);
    return monoBmp;
}

//------------------------------------------------------------------------------
// WindowMix
//------------------------------------------------------------------------------
///
template WindowClassMix(string MSGPROC, A...)
{
    import std.conv : to;

    alias typeof(this) THIS;

    static if (0 < A.length && is(typeof(A[0]) : wstring))
    {
        enum CLASS_NAME = A[0];
        alias A[1 .. $] CASES;
    }
    else
    {
        enum CLASS_NAME = THIS.stringof.to!wstring;
        alias A CASES;
    }

    //----------------------------------------------------------
    static public WNDCLASSEX* ready(HMODULE hInst = null)
    {
        import std.utf : toUTF16z;
        auto wc = new WNDCLASSEX;
        auto name = CLASS_NAME.toUTF16z;
        if (0 != GetClassInfoEx(hInst ? hInst : GetModuleHandle(null),
                                name, wc)) return null;

        static if (__traits(hasMember, THIS, "wm_paint"))
            wc.ready!0(name, mixin("&" ~ MSGPROC), hInst);
        else
            wc.ready(name, mixin("&" ~ MSGPROC), hInst);
        return wc;
    }
}

/** $(LINK2 http://www.kumei.ne.jp/c_lang/sdk/sdk_33.htm, メッセージクラッカ)を
生成する。

create を呼び出すと、ウィンドウのユーザデータとして mixin 先の
クラスインスタンスを登録する。$(BR)
登録されたインスタンスには getInstance よりアクセスできる。$(BR)

Notice:
  create 内で &this を取っている為、構造体に mixin する場合はコンストラクタ内
  で create を呼ぶべきではない。
**/
mixin template MessageCrackerMix(string PROC)
{
    static if      (is(typeof(this) == class))
        alias THIS = typeof(this);
    else static if (is(typeof(this) == struct))
        alias THIS = typeof(this)*;

    // ウィンドウのユーザデータとして登録される構造体。
    // インスタンスとかが入ってる。
    private struct _CP
    {
        ///
        struct ProcChain
        {
            ///
            alias Proc = void function(Msg, ref Object);
            private Proc _proc;
            ProcChain* next; ///
            Object param; ///

            ///
            @trusted @nogc pure nothrow
            this(Proc p, ProcChain* n, Object pa = null)
            { _proc = p; next = n; param = pa; }

            ///
            void call(Msg m)
            {
                _proc(m, param);
                if (next) next.call(m);
            }
        }
        THIS instance; ///
        void* lparam;  ///
        ProcChain* chain; ///
    }

    /// メッセージプロシジャ本体。
    extern(Windows) static public nothrow
    LRESULT MsgCracker(HWND hWnd, UINT uMsg, WPARAM wp, LPARAM lp)
    {
        import std.exception : enforce;
        import sworks.win32.util : okbox;

        scope auto msg = new Msg(hWnd, uMsg, wp, lp);
        try mixin(PROC);
        catch (WinException we)
        {
            try okbox(we.toStringWz);
            catch (Throwable) {}
        }
        catch (Throwable t)
        {
            try okbox((new WinException(t.toString)).toStringWz);
            catch (Throwable) {}
        }

        return msg.defProc;
    }

    //==========================================================
    ///
    Wnd create(uint style, const(wchar)* title = null,
               Wnd parent = Wnd(null), HMENU menu = null, uint exStyle = 0,
               int x = CW_USEDEFAULT, int y = CW_USEDEFAULT,
               int w = CW_USEDEFAULT, int h = CW_USEDEFAULT,
               void* param = null, HINSTANCE hInst = null)
    {
        import std.utf : toUTF16z;
        static if      (is(typeof(this) == class))
            auto cp = _CP(this, param);
        else static if (is(typeof(this) == struct))
            auto cp = _CP(&this, param);
        if (hInst is null) hInst = GetModuleHandle(null);
        return Wnd(CreateWindowEx(exStyle, CLASS_NAME.toUTF16z, title, style,
                                   x, y, w, h, parent.ptr, menu, hInst, &cp)
            .enforceW("fail at CreateWindowEx("w ~ CLASS_NAME[] ~ ")."w));
    }

    /// when wm_create is called, the handle is ready.
    LRESULT wm_nccreate(Msg msg) { return msg.defProc; }
    LRESULT wm_create(Msg msg) { return msg.defProc; }
    LRESULT wm_ncdestroy(Msg msg) { return msg.defProc; }
    /// when wm_destroy is end, the handle is disable.
}


//------------------------------------------------------------------------------
// メッセージループ関連
//------------------------------------------------------------------------------
/// 一定間隔で update を呼び出す。
void loop(uint INTERVAL)(scope bool delegate(MSG*) dispatch,
                         scope void delegate(uint) update)
{
    outer_loop:
    for (uint now, next = GetTickCount() + INTERVAL; ; next += INTERVAL)
    {
        for (MSG msg; PeekMessage(&msg, null, 0, 0, PM_REMOVE);)
            if (!dispatch(&msg)) break outer_loop;
        now = GetTickCount();
        if (now < next)
        {
            Sleep(next - now);
            update(INTERVAL);
        }
    }
}


////////////////////XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\\\\\\\\\\\\\\\\\\\\
debug(util):
import sworks.win32.multi_window;

final class Test
{ mixin MultiWindowMix!() MWM;

    mixin SubMenuMix!(q{
        <menu name="top" base="300">
            <item id="HOGE">hoge</item>
            <menu name="popup 1">
                <item>fuga</item>
            </menu>
        </base>
    }) SM;

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
            fill!"BLACK"(0, 0, 100, 100);
            fill!"GRAY"(30, 30);
            line!q{ 200, 200 .. 100, 300 .. 200, 400 .. 300, 300 ..};
            line!q{ 200, 200 -- 100, 300 -- 200, 400 -- 300, 300 --};
            text!"NW"("hello");
        }
    }

    LRESULT wm_command(Msg msg)
    {
        if (0 == msg.hwp)
        {
            dump(msg.lwp);
        }
        return 0;
    }

    LRESULT wm_rbuttondown(Msg msg)
    {
        auto pos = POINT(msg.sllp, msg.shlp);
        ClientToScreen(wnd.ptr, &pos);
        SM.start!"top"(wnd.ptr, pos.x, pos.y);
        return 0;
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
