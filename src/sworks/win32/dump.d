/**
 * Version:    0.0001(dmd2.071.0)
 * Date:       2015-Jul-26 02:15:39
 * Authors:    KUMA
 * License:    CC0
*/
module sworks.win32.dump;

import sworks.base.array;
import sworks.win32.util;
import sworks.win32.single_window;

/// デバグ用に。dump("hogehoge"); とかで表示される。
final class dump
{
    mixin SingleWindowMix!() SWM;

    //
    static private dump _instance;

    //
    static this()
    {
        debug SWM.ready.regist;
    }

    //
    static ~this()
    {
        debug
        {
            if (_instance) _instance.wnd.clear;
            _instance = null;
        }
    }

    //
    static private dump query() @property
    {
        if (_instance is null) _instance = new dump;
        return _instance;
    }

    //
    static private void _destroyNotice()
    {
        _instance = null;
    }


    /// メインインターフェイス
    static void opCall(T...)(T msg)
    {
        debug query._dump(msg);
    }

    /// ditto
    static void opCall(string fmt, T...)(T msg)
    {
        debug query._dumpf(fmt, msg);
    }

    /// けす。
    static void cls()
    {
        debug query._cls;
    }


    //
    private StrzW _cont;
    private Wnd _edit;
    private enum EDIT_ID = 0x0011;

    //
    private this()
    {
        SWM.create(WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_VISIBLE, "DUMP");
    }

    //
    private void _cls()
    {
        _cont = ""w;
        _edit.text = _cont.ptrz;
    }

    //
    private void _dump(T...)(T msg)
    {
        import std.string : join;
        import std.conv : to;
        wstring[] str;
        foreach (one ; msg) str ~= [" ", one.to!wstring];
        str ~= "\r\n";
        _cont ~= str.join;
        _edit.text =_cont.ptrz;
        _scrollToLast;
    }

    //
    private void _dumpf(string fmt, T...)(T msg)
    {
        import std.array : appender;
        import std.format : formattedWrite;

        auto str = appender!string();
        formattedWrite(str, fmt, msg);
        str.put("\r\n");
        _cont ~= str.data;
        _edit.text = _cont.ptrz;
        _scrollToLast;
    }

    private void _scrollToLast()
    {
        auto l = _edit.send(EM_GETLINECOUNT);
        _edit.send(EM_LINESCROLL, 0, l);
    }

    //
    //
    LRESULT wm_create(Msg)
    {
        _edit = Create("EDIT"w.ptr,
                       WS_VISIBLE | WS_CHILD | WS_HSCROLL | WS_VSCROLL
                        | ES_MULTILINE | ES_AUTOVSCROLL,
                       0, wnd, EDIT_ID);
        return 0;
    }

    //
    LRESULT wm_size(Msg msg)
    {
        if (SIZE_RESTORED != msg.wp) return 0;
        _edit.move(0, 0, msg.llp, msg.hlp);
        return 0;
    }

    //
    LRESULT wm_destroy(Msg)
    {
        _destroyNotice;
        return 0;
    }
}
