/** single_window.d
 * Version:    0.0001(dmd2.071.0)
 * Date:       2015-Nov-20 01:17:28
 * Authors:    KUMA
 * License:    CC0
 */
module sworks.win32.single_window;

/**
 * メッセージクラッカを生成
 * CASES はメッセージの値および、メッセージを受け取る関数名の文字列の2つを一組
 * とするタプル
 * 例: WM_COMMAND,"command", WM_PAINT,"draw", ...
 *
 * 関数名が、wm_command とか、 wm_paint とかの場合は自動で追加される。
 *
 */
template SingleWindowMix(A ...)
{
    import sworks.win32.util;
    import sworks.win32.gdi;

    mixin WindowClassMix!("MsgCracker", A);
    mixin MessageCrackerMix!(
    {
        import std.string : toUpper, join;
        import std.algorithm : startsWith;
        string[] result;
        result =
        [q{
            assert(_instance !is null || WM_GETMINMAXINFO == msg.msg
                                       || WM_NCCREATE == msg.msg,
                   "instance is null");
            if (_chain) _chain.call(msg);
        }, "switch(msg.msg){",
         q{
            case WM_NCCREATE:
                assert(_instance is null, "an instance of " ~ THIS.stringof
                                         ~ " can be made only once.");
                auto pcp = cast(_CP*)((msg.plp!(CREATESTRUCT*)).lpCreateParams);
                _instance = pcp.instance.enforce;
                typeof(this).wnd = Wnd(hWnd);
                msg.plp!(CREATESTRUCT*).lpCreateParams = pcp.lparam;
                return _instance.wm_nccreate(msg);
            case WM_CREATE:
                msg.plp!(CREATESTRUCT*).lpCreateParams =
                    (cast(_CP*)((msg.plp!(CREATESTRUCT*)).lpCreateParams)).
                        lparam;
                return _instance.wm_create(msg);
            case WM_NCDESTROY:
                scope(exit){ typeof(this).wnd = Wnd(null); _instance = null; }
                return _instance.wm_ncdestroy(msg);
        }];

        static if (__traits(hasMember, typeof(this), "wm_paint"))
        {
            static if     (IsMsgHandler!(
                typeof(__traits(getMember, typeof(this), "wm_paint"))))
            {
                result ~= q{
                    case WM_PAINT:
                        return _instance.wm_paint(msg);
                };
            }
            else static if (IsPaintHandler!(
                typeof(__traits(getMember, typeof(this), "wm_paint"))))
            {
                result ~= q{
                    case WM_PAINT:
                    {
                        PAINTSTRUCT ps;
                        auto hdc = BeginPaint(msg.wnd.ptr, &ps);
                        _instance.wm_paint(Dc(hdc), ps);
                        EndPaint(msg.wnd.ptr, &ps);
                    }
                    return 0;
                };
            }
            else static assert(0);
        }

        template userCases(string N)
        {
            enum bool userCases = N != "wm_nccreate" && N != "wm_create"
                                    && N != "wm_ncdestroy" && N != "wm_paint";
        }

        foreach (one ; CASES)
        {
            static if     (is(typeof(one) : uint))
                result ~= ["case ", to!string(one), " : "];
            else static if (is(typeof(one) : string))
            {
                static assert (userCases!one);
                result ~= ["return _instance.", one, "(msg);"];
            }
            else static assert(0, to!string(one)
                ~ " is not correct as a parameter for SingleWindowMix.");
        }

        foreach (one ; __traits(derivedMembers, THIS))
        {
            static if (one.startsWith("wm_") && userCases!one)
            {
                static assert(IsMsgHandler!(
                    typeof(__traits(getMember, THIS, one))));
                result ~= ["case ", one.toUpper, " : return _instance.",
                           one, "(msg);"];
            }
        }

        result ~= " default: }";
        return result.join;
    }());

    //==========================================================
    static public Wnd wnd;
    alias wnd this;

    static
    void installProcChain(_CP.ProcChain.Proc p, Object param = null)
    { _chain = new _CP.ProcChain(p, _chain, param); }

    static @property @trusted @nogc nothrow
    THIS getInstance() { return _instance; }

    static private THIS _instance;
    static private _CP.ProcChain* _chain;
}

//##############################################################################
debug(single_window)
{
    import std.stdio;

    final class TestWindow
    { mixin SingleWindowMix!() SWM;

        this()
        {
            auto wc = SWM.ready();
            (*wc).regist;

            SWM.create(WS_OVERLAPPEDWINDOW | WS_VISIBLE, "test"w.ptr);
        }


        LRESULT wm_close(Msg msg)
        {
            wnd.okbox("closing"w);
            DestroyWindow(msg.wnd.ptr);
            return 0;
        }
        LRESULT wm_destroy(Msg)
        {
            scope(exit) PostQuitMessage(0);
            return 0;
        }
    }
    
    void main()
    {
        try
        {
            scope auto tw = new TestWindow();

            MSG msg;
            while(GetMessage(&msg, null, 0, 0) > 0) { /*TranslateMessage(&msg);*/ DispatchMessage(&msg); }
        }
        catch (WinException w) okbox(w.toStringW);
        catch (Throwable t) okbox(t.toString.toUTF16);
    }
}
