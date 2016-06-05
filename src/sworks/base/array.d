/** variantな要素の為の効率のよい(?)動的配列の実装
 * Version:    0.0001(dmd2.071.0)
 * Date:       2016-Jan-16 00:46:56
 * Authors:    KUMA
 * License:    CC0
 */
module sworks.base.array;

//------------------------------------------------------------------------------
/// T 型の動的配列。中身はほとんど std.array.Appender
struct Array(T)
{
    import std.array : Appender;
    import std.traits : Unqual;

    alias E = Unqual!T;
    public Appender!(E[]) _app;
    alias _app this;

    ///
    @trusted pure nothrow
    this(E[] arr ...) { _app = Appender!(E[])(arr); }

    ///
    @trusted @nogc pure nothrow
    size_t length() const { return _app.data.length; }
    ///
    @trusted @nogc pure nothrow
    size_t opDollar(size_t pos)() const { return _app.data.length; }
    ///
    @trusted @nogc pure nothrow
    auto ptr() inout { return _app.data.ptr; }

    ///
    @trusted @nogc pure
    ref auto opIndex(size_t i) inout { return _app.data[i]; }
    ///
    @trusted @nogc pure
    void opIndexAssign(E v, size_t i) { _app.data[i] = v; }
    ///
    @trusted @nogc pure nothrow
    auto opSlice() inout { return _app.data[]; }
    ///
    @trusted @nogc pure
    auto opSlice(size_t i, size_t j) inout { return _app.data[i .. j]; }
    ///
    @trusted pure nothrow
    void opAssign(const(E)[] arr ...)
    { _app = Appender!(E[])(cast(E[])arr); }
    ///
    @trusted @nogc pure nothrow
    void opSliceAssign(E val){ _app.data[0 .. $] = val; }
    ///
    @trusted @nogc pure
    void opSliceAssign(const(E)[] val){ _app.data[0 .. $] = cast(E[])val; }
    ///
    @trusted @nogc pure nothrow
    void opSliceAssign(E val, size_t i, size_t j)
    { _app.data[i .. j] = val; }
    ///
    @trusted @nogc pure
    void opSliceAssign(const(E)[] val, size_t i, size_t j)
    { _app.data[i .. j] = cast(E[])val; }


    /// アイテムの順番が変わる。
    @trusted pure
    void fastRemove(size_t target)
    {
        _app.data[target] = _app.data[$-1];
        _app.shrinkTo(_app.data.length-1);
    }

    /// from <= to <= buffer.length
    @trusted pure
    sizediff_t replace(size_t from, size_t to, in const(E)[] a ...)
    {
        import std.algorithm : min, swap;

        from = min(from, _app.data.length);
        to = min(to, _app.data.length);
        if (to < from) swap(from, to);

        size_t len = to - from;

        // 長さが一緒
        if     (a.length == len)
        {
            _app.data[from .. from + a.length] = cast(E[])a;
        }
        // 短かくなる
        else if (a.length < len)
        {
            size_t amount = _app.data.length - to;
            size_t oldorg = to;
            size_t neworg = from + a.length;
            for (size_t i = 0 ; i < amount ; i++)
            {
                _app.data[neworg + i] = _app.data[oldorg + i];
            }
            _app.shrinkTo(neworg + amount);
            _app.data[from .. from + a.length] = cast(E[])a;
        }
        //延びる。a の尻が元の配列より出る。
        else if (_app.data.length < from + a.length)
        {
            size_t oldlength = _app.data.length;
            size_t a_copy = a.length - (from + a.length - oldlength);
            _app.put(cast(E[])a[a_copy .. $]);
            _app.put(_app.data[to .. oldlength]);
            _app.data[from .. oldlength] = cast(E[])a[0 .. a_copy];
        }
        // 出ない
        else
        {
            size_t app_copy = _app.data.length - (from - to + a.length);
            size_t neworg = _app.data.length;
            _app.put(_app.data[app_copy .. $]);
            size_t amount = app_copy - to;
            for (size_t i = 1 ; i <= amount ; i++)
            {
                _app.data[neworg - i] = _app.data[app_copy - i];
            }
            _app.data[from .. from + a.length] = cast(E[])a;
        }

        return a.length - len;
    }

}

//------------------------------------------------------------------------------
/// ソート済み配列の操作に。
struct SortedArray(T, alias pred = "a < b")
{
    Array!T _payload;
    alias _payload this;

    ///
    this(T[] arr)
    {
        import std.algorithm : sort;
        import std.array : array;
        _payload = Array!T(arr.sort!pred.array);
    }

    //
    @trusted @nogc pure nothrow
    static private size_t bsearch(alias pred)(in T[] arr, in T needle)
    {
        import std.functional;
        if (arr.length < 1) return 0;
        auto pivot = arr.length / 2;
        if (binaryFun!pred(arr[pivot], needle) <= 0)
            return bsearch!pred(arr[0..pivot], needle);
        else
            return pivot + 1 + bsearch!pred(arr[pivot+1 .. $], needle);
    }

    ///
    @trusted pure
    size_t insert(T item)
    {
        auto pos = bsearch!pred(_payload[], item);
        _payload.replace(pos, pos, item);
        return pos;
    }

    ///
    @trusted pure
    size_t remove(T item)
    {
        auto pos = bsearch!pred(_payload[], item);
        _payload.replace(pos, pos+1);
        return pos;
    }

}


//------------------------------------------------------------------------------
/** 読み取り専用の Null終端文字列を扱う.
 * C言語へのアクセス用。
 */
struct TReadz(TCHAR)
{

private:
    immutable(TCHAR)[] value = "\0";

public:

    ///
    @trusted pure nothrow
    this(T)(T v)
    {
        import std.conv : to;
        import std.traits : isPointer, isSomeString;
        import std.exception : assumeUnique;
        static if     (isPointer!T)
        {
            if (v is null) value = "\0";
            else
            {
                size_t i;
                for (i = 0 ; v[i] != '\0' ; ++i){}
                static if (is(T : TCHAR*))
                    value = assumeUnique(v[0 .. i+1]);
                else
                    value = to!(immutable(TCHAR)[])(v[0 .. i+1]);
            }
        }
        else static if (is(T : TReadz))
        {
            value = v.value;
        }
        else static if (isSomeString!T)
        {
            auto str = to!(const(TCHAR)[])(v);
            TCHAR[] v2 = new TCHAR[str.length + 1];
            v2[0 .. $-1] = str;
            v2[$-1] = '\0';
            value = assumeUnique(v2);
        }
        else static assert(0);
    }

    ///
    @nogc pure
    this(T : immutable(TCHAR)*)(T ptr, size_t l)
    {
        value = ptr[0 .. l + 1];
    }

    ///
    @trusted @nogc pure nothrow
    immutable(TCHAR)* ptr() const { return value.ptr; }
    ///
    @trusted @nogc pure nothrow
    immutable(TCHAR)* ptrz() const { return value.ptr; }
    ///
    @trusted @nogc pure nothrow
    size_t length() const { return value.length - 1; }
    ///
    @trusted @nogc pure nothrow
    immutable(TCHAR)[] bare_value() const { return value; }

    ///
    @trusted nothrow
    TReadz dup() const { return TReadz(this); } // no copy

    // operator overloads
    ///
    @trusted @nogc pure
    TCHAR opIndex(size_t i) const { return value[i]; }
    ///
    @trusted @nogc pure
    immutable(TCHAR)[] opSlice() const{ return value[0 .. $-1]; }
    ///
    @trusted @nogc pure
    immutable(TCHAR)[] opSlice(size_t i, size_t j) const
    { return value[i .. j]; }

    ///
    @trusted @nogc pure nothrow
    const(TReadz) getReader() const { return this; }

    ///
    @trusted pure
    string toString() const
    { import std.conv : to; return value[0 .. $-1].to!string; }
    ///
    @trusted pure
    wstring toStringW() const
    { import std.conv : to; return value[0 .. $-1].to!wstring; }
    ///
    @trusted pure
    dstring toStringD() const
    { import std.conv : to; return value[0 .. $-1].to!dstring; }
}
/// ditto
alias TReadz!wchar ReadzW;
/// ditto
alias TReadz!char ReadzA;
/// ditto
version (Unicode) alias ReadzW Readz;
else alias ReadzA Readz;


/// suger
template t_ptrz(TCHAR)
{
    @trusted pure
    const(TCHAR)* t_ptrz(T)(T value) { return TReadz!TCHAR(value).ptr; }
}
/// ditto
alias t_ptrz!wchar ptrzW;
/// ditto
alias t_ptrz!char ptrzA;
/// ditto
version (Unicode) alias ptrzW ptrz;
else alias ptrzA ptrz;

//------------------------------------------------------------------------------
//
/// 書き替え可能な Null 終端文字列
struct TStrz(TCHAR)
{
private:
    alias TReadz!TCHAR Readz;
    Array!TCHAR _payload; // 最後に '\0' を含む。
    TCHAR[] _value; // _payload の最後の '\0' を含まないスライス

public:

    ///
    @trusted pure
    this(T)(const T v) { opAssign(v); }

    ///
    @trusted @nogc pure nothrow
    const(TCHAR)* ptr() const { return _value.ptr; }
    ///
    @trusted @nogc pure nothrow
    const(TCHAR)* ptrz() const { return _value.ptr; }
    ///
    @trusted @nogc pure nothrow
    const(TCHAR)[] bare_value() const { return _payload.data; }

    ///
    @trusted @nogc pure nothrow
    size_t length() const { return _value.length; }

    ///
    @trusted pure
    TStrz dup() const { return TStrz(_value);}

    ///
    @trusted pure
    ref TStrz shrinkTo(size_t l)
    {
        if (l < _value.length) _payload.shrinkTo(l+1);
        if (0 < _payload.length)
        {
            _payload[$-1] = '\0';
            _value = _payload[0..$-1];
        }
        else _value = _payload[0..0];
        return this;
    }

    ///
    @trusted pure
    ref TStrz replace(size_t f, size_t t, in const(TCHAR)[] a)
    {
        _payload.replace(f, t, a);
        if (0 < _payload.length)
        {
            _payload[$-1] = '\0';
            _value = _payload[0..$-1];
        }
        else _value = _payload[0..0];
        return this;
    }

    ///
    @trusted @nogc pure nothrow
    size_t opDollar(size_t pos)(){ return _value.length; }

    ///
    @trusted pure
    ref TStrz opAssign(const(TCHAR)[] r)
    {
        _payload.clear;
        _payload.put(r);
        _payload.put('\0');
        _value = _payload[0..$-1];
        return this;
    }
    ///
    @trusted pure
    ref TStrz opAssign(const(TCHAR)* r)
    {
        if (r is null) return this;
        size_t i;
        for (i = 0; r[i] != '\0'; ++i){}
        _payload.clear;
        _payload.put(r[0..i+1]);
        _value = _payload[0..$-1];
        return this;
    }
    ///
    @trusted pure
    ref TStrz opAssign(const Readz r)
    {
        _payload.clear;
        _payload.put(r[]);
        _payload.put('\0');
        _value = _payload[0..$-1];
        return this;
    }

    ///
    @trusted pure
    ref TStrz opOpAssign(string OP : "~", T : const(TCHAR)[])(T str)
    {
        _payload.shrinkTo(_value.length);
        _payload.put(str);
        _payload.put('\0');
        _value = _payload[0..$-1];
        return this;
    }
    ///
    @trusted pure
    ref TStrz opOpAssign(string OP : "~", T : const(TCHAR)*)(T str)
    {
        size_t i;
        for (i = 0; str[i] != '\0'; ++i){}
        _payload.shrinkTo(_value.length);
        _payload.put(str[0..i+1]);
        _value = _payload[0..$-1];
        return this;
    }

    ///
    @trusted pure
    ref TStrz opOpAssign(string OP : "~", T)(T str)
        if (is(T : const TStrz) || is(T : const Readz))
    {
        import std.traits : Unqual;
        _payload.shrinkTo(_value.length);
        _payload.put((cast(Unqual!T)str)[]);
        _payload.put('\0');
        _value = _payload[0..$-1];
        return this;
    }

    ///
    @trusted pure
    ref TStrz put(T)(T str){ return opOpAssign!("~", T)(str); }

    ///
    @trusted pure
    TStrz opBinary(string OP : "~", T)(T str) const
    {
        auto ret = this.dup;
        ret ~= str;
        return ret;
    }

    ///
    @trusted pure
    TStrz opBinaryRight(string OP : "~", T)(T str) const
    {
        auto ret = TStrz(str);
        ret ~= this;
        return ret;
    }

    ///
    @trusted @nogc pure
    TCHAR opIndex(size_t i){ return _value[i]; }
    ///
    @trusted @nogc pure
    TCHAR opIndexAssign(TCHAR v, size_t i)
    {
        _value[i] = v;
        return v;
     }

    ///
    @trusted @nogc pure nothrow
    const(TCHAR)[] opSlice() const { return _value[]; }
    ///
    @trusted @nogc pure
    const(TCHAR)[] opSlice(size_t i, size_t j) { return _value[i .. j]; }
    ///
    @trusted @nogc pure nothrow
    const(TCHAR)[] opSliceAssign(TCHAR v)
    {
        _value[] = v;
        return _value[];
    }
    ///
    @trusted @nogc pure
    const(TCHAR)[] opSliceAssign(const(TCHAR)[] v)
    {
        _value[] = v;
        return _value[];
    }
    ///
    @trusted @nogc pure
    const(TCHAR)[] opSliceAssign(const(TCHAR)[] v, size_t i, size_t j)
    {
        _value[i .. j] = v;
        return _value[i .. j];
    }


    ///
    @trusted pure
    Readz getReader() { return Readz(_value.idup); }
    ///
    @trusted pure
    string toString()
    { import std.conv : to; return _value.to!string; }
    ///
    @trusted pure
    wstring toStringW()
    { import std.conv : to; return _value.to!wstring; }
    ///
    @trusted pure
    dstring toStringD()
    { import std.conv : to; return _value.to!dstring; }
}
/// ditto
alias TStrz!wchar StrzW;
/// ditto
alias TStrz!char StrzA;
/// ditto
version (Unicode) alias StrzW Strz;
else alias StrzA Strz;


debug(array)
{
    import std.stdio;
    void main()
    {
        auto buf = Array!(char)();

        buf.replace(0, 0, "hello good-bye.");
        buf.put(' ');
        buf.replace(6, 6, "world, ");
        writeln("1:", buf[]);

        buf.replace(2, 4, "lll");
        writeln("2:", buf[]);

        buf.replace(7, 14);
        writeln("3:", buf[]);

    }
}
