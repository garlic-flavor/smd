/** キャッシュ付き逐次ファイル読み込み。様々なファイルのパースにも!
 * Date:       2016-Apr-17 00:02:04
 * Authors:    KUMA
 * License:    CC0
 */
module sworks.util.cached_buffer;
debug import std.stdio : writeln;
import sworks.base.aio;
import sworks.base.traits;

//------------------------------------------------------------------------------
///
interface TICache(T) : sworks.base.aio.IAIO, sworks.base.aio.IForwardRange!T,
                      sworks.base.aio.IPeekRange!T, sworks.base.aio.ISave,
                      sworks.base.aio.ITell!T, sworks.base.aio.TIReadSeq!T
{
    import std.traits : Unqual;
    alias U = Unqual!T;

    /// 先頭 s 文字をスタックに詰む。カーソルを進め、次の1文字をpeekする。
    U push(size_t s = 1);
    /// 先頭1字の代りに c をスタックに詰む。
    /// カーソルを進め、次の1文字をpeekする。
    U push(U c);
    /// スタックの内容を得る。
    @property
    const(U)[] stack() const;
    @property
    immutable(U)[] istack() const;
    /// スタックの内容をクリアする。
    void flush();

    /// 残り。
    @property
    const(U)[] rest() const;

    /// 最初から現在位置までをダンプする。デバグ用。
    const(U)[] dump();

    ///
    debug Benchmark getBenchmark() @property const;
}

//------------------------------------------------------------------------------
/// CTFE 時とか、まるっとキャッシュしておける場合に。
import std.traits : Unqual;
class TWholeCache(T) : TICache!(Unqual!T)
{
    private const(T)[] _cache;
    private const(T)[] _rest;
//    private Appender!(T[]) _stack;
    private U[] _stack;

    ///
    static if (is(T == immutable))
    {
        @nogc @trusted pure nothrow
        this(T[] c)
        {
            this._cache = c;
            this._rest = this._cache[];
        }
    }
    else
    {
        @nogc @trusted pure nothrow
        this(const(T)[] c)
        {
            this._cache = c;
            this._rest = this._cache[];
        }
    }

    @property @trusted @nogc pure const nothrow
    {
        size_t size() { return _cache.length; }
        bool empty() { return 0 == _rest.length; }
        U front() { return 0 < _rest.length ? _rest[0] : T.init; }
        const(U)[] cache() { return _cache; }
        const(U)[] rest() { return _rest; }
    }

    @trusted @nogc pure nothrow
    U popFront(size_t s = 1)
    {
        if (s < _rest.length) _rest = _rest[s .. $];
        else _rest = _rest[$ .. $];
        return front;
    }

    @trusted @nogc pure const nothrow
    const(U)[] peek(size_t s = 1)
    {
        if (_rest.length < s) s = _rest.length;
        return _rest[0 .. s];
    }

    @property @trusted @nogc pure const nothrow
    const(U)[] peekBetter() { return _rest[]; }

    @trusted @nogc pure nothrow
    void close() { _cache = null; _stack = null; _rest = null; }
    @trusted @nogc pure nothrow
    U[] read(U[] buf)
    {
        auto result = buf[0 .. $];
        if (_rest.length < result.length) result = result[0 .. _rest.length];
        result[] = _rest[0 .. result.length];
        _rest = _rest[result.length .. $];
        return result;
    }
    @trusted @nogc pure nothrow
    void discard(long s) { popFront(cast(size_t)s); }

    @trusted pure
    U push(size_t s = 1)
    {
        if (_rest.length < s) s = _rest.length;
        if      (0 == _stack.length)
            _stack = cast(U[])_rest[0..s];
        else if ((_stack.ptr + _stack.length) == _rest.ptr)
            _stack = cast(U[])_stack.ptr[0.._stack.length + s];
        else
            _stack ~= _rest[0 .. s];

        _rest = _rest[s .. $];
        return front;
    }
    @trusted pure
    U push(U c)
    {
        _stack ~= c;
        if (0 < _rest.length) _rest = _rest[1 .. $];
        return front;
    }
    @property @trusted pure nothrow
    const(U)[] stack() const { return _stack[];}
    @property @trusted pure
    immutable(U)[] istack() const
    {
        import std.exception : assumeUnique;
        static if (is(T == immutable))
        {
            if (_cache.ptr <= _stack.ptr
              && _stack.ptr < _cache.ptr + _cache.length)
                return _stack[].assumeUnique;
            else
                return _stack.idup;
        }
        else
            return _stack.idup;
    }
    @trusted @nogc pure nothrow
    void flush() { _stack = null; }

    @property @trusted pure
    TWholeCache save() const
    {
        auto ret = new TWholeCache(_rest);
        ret._stack = _stack.dup;
        return ret;
    }

    @property @trusted pure nothrow
    ulong tell() const { return _cache.length - _rest.length; }

    @property @trusted pure nothrow
    string name() const { return "STRING"; }

    @trusted pure nothrow
    const(U)[] dump() const { return _cache[0.. $ - _rest.length]; }

    debug Benchmark getBenchmark() @property const { return Benchmark(); }
}


//==============================================================================
/**
ファイルへの入出力の実装を外部へ公開しているので汎用的!
キャッシュを利用してファイルへのアクセス回数をなるべく減らしつつ、
巨大なファイルでも使用メモリが増えないように。
**/
class TCachedBuffer(T) : TICache!T
{
    import std.array : Appender;

    const size_t CACHE_SIZE;

    private SliceMaker!T _cache;
    private SliceMaker!T.Slice _rest;
    // push の量が少ない場合は _cache を使う。
    private SliceMaker!T.Slice _stack;
    // CACHE_SIZE / 2 よりたくさん push した時に使われる。
    private Appender!(U[]) _buffer;

    private TIReadSeq!T _io; // キャッシュなし io の実装。

    ///
    @trusted
    this(TIReadSeq!T f, size_t cache_size = 1024)
    {
        CACHE_SIZE = cache_size;
        _cache = new SliceMaker!T(new T[CACHE_SIZE + /*番兵*/ 1]);
        _io = f;
        _rest = _cache.slice;
        _stack = _cache.slice;
        _refill_cache;
    }

    ///
    @trusted pure nothrow
    this(TIReadSeq!T f, SliceMaker!T c, size_t rh, size_t rt,
         size_t sh, size_t st, T[] buf, size_t cache_size)
    {
        CACHE_SIZE = cache_size;
        _cache = c;
        _rest = c.slice(rh, rt);
        _stack = c.slice(sh, st);
        _buffer.put(buf);
    }

    private void _refill_cache()
    {
        debug { with (_bmark) {
            use_average *= refill_times;
            rest_average *= refill_times;

            refill_times++;
            float r = _stack.length + _rest.length;
            if (rest_max < r)
            {
                rest_max = r;
                rest_max_time = refill_times;
            }
            rest_average = (rest_average + r) / refill_times;
        } }

        _stack.moveTo(0);
        _rest.moveTo(_stack.tail);
        if (_rest.tail < CACHE_SIZE)
            _rest.set(_rest.head, _rest.tail
                     + _io.read(_cache[_rest.tail .. CACHE_SIZE]).length);
        _cache[_rest.tail] = T.init;

        debug { with (_bmark) {
            float u = cast(float)_rest.length;
            use_max = use_max < u ? u : use_max;
            use_average = (use_average + u) / refill_times;
        } }
    }

    @property @trusted pure nothrow
    {
        size_t size() const { return CACHE_SIZE; }
        bool empty() const { return _rest.empty; }
        const(U)[] rest() const { return _rest[]; }
        U front() const { return *_rest.ptr; }
    }

    U popFront(size_t s = 1)
    {
        if     (s < _rest.length) _rest.popFront(s);
        else
        {
            if (_rest.length < s) _io.discard(s - _rest.length);
            _rest.clear(_stack.tail);
            _refill_cache;
        }
        return *_rest.ptr;
    }

    const(U)[] peek(size_t s)
    {
        if (_rest.length < s) _refill_cache;
        if (_rest.length < s) s = _rest.length;
        return _rest[0 .. s];
    }
    const(U)[] peekBetter()
    {
        if (_rest.length < (CACHE_SIZE>>1)) _refill_cache;
        return _rest[];
    }

    U[] read(U[] buf)
    {
        U[] result = buf[0 .. $];
        if (result.length <= _rest.length)
        {
            result[] = _rest[0 .. result.length];
            _rest.popFront(result.length);
        }
        else
        {
            result[0 .. _rest.length] = _rest[];
            result = result[0 .. _rest.length
                           + _io.read(result[_rest.length .. $]).length];
            _rest.clear(_stack.tail);
        }
        if (_rest.empty) _refill_cache;
        return result;
    }
    void discard(long s){ popFront(s); }

    void close()
    {
        _io.close();
        _cache = _cache[0 .. 1];
        _cache[0] = T.init;
        _rest.clear;
        _stack.clear;
        _buffer.clear;
    }

    U push(size_t s = 1)
    {
        if     ((CACHE_SIZE>>1) < _stack.length)
        {
            _buffer.put(_stack[]);
            _stack.clear(_rest.head);
        }
        else if (_stack.empty) _stack.clear(_rest.head);

        if (_rest.length < s) _refill_cache;
        if (_rest.length < s) s = _rest.length;

        _stack.pushBack(_rest[0 .. s]);
        _rest.popFront(s);
        if (_rest.empty) _refill_cache;

        return *(_rest.ptr);
    }
    U push(T c)
    {
        if     ((CACHE_SIZE>>1) < _stack.length)
        {
            _buffer.put(_stack[]);
            _stack.clear(0);
        }
        else if (_stack.empty) _stack.clear(0);

        if (_rest.length < 1) _refill_cache;
        if (0 == _rest.length) return T.init;

        _stack.pushBack(c);
        _rest.popFront;
        if (_rest.empty) _refill_cache;

        return *(_rest.ptr);
    }

    @property @trusted pure
    const(U)[] stack() const
    {
        return 0 < _buffer.data.length ? _buffer.data[] ~ _stack[] : _stack[];
    }
    @property @trusted pure
    immutable(U)[] istack() const
    {
        import std.exception : assumeUnique;
        if (0 < _buffer.data.length)
            return (_buffer.data[] ~ _stack[]).assumeUnique;
        else
            return _stack[].idup;
    }

    @trusted pure
    void flush() { _buffer.clear; _stack.clear(_rest.head); }

    @property @trusted
    ulong tell() const
    { return _io.tell - _rest.length; }

    @property @trusted
    string name() const
    { return _io.name; }

    const(U)[] dump()
    {
        if (auto ra = cast(IRandomAccess)_io)
        {
            auto buf = new Unqual!T[cast(size_t)_io.tell - _rest.length];
            ra.seekSet(0);
            _io.read(buf);
            return buf;
        }
        return null;
    }

    @trusted
    TCachedBuffer save() const
    {
        import std.conv : to;
        return new TCachedBuffer(_io.to!(const(ISave)).save.to!(TIReadSeq!T),
                                 _cache.dup,
                                 _rest.head, _rest.tail, _stack.head,
                                 _stack.tail, _buffer.data.dup, CACHE_SIZE);
    }

    debug
    {
        private Benchmark _bmark;
        Benchmark getBenchmark() @property const { return _bmark; }
    }
}

//------------------------------------------------------------------------------
//==============================================================================
//
// suger
//
//==============================================================================
//------------------------------------------------------------------------------

/// 配列をキャッシュに。
auto toCache(T)(T[] cont) @trusted pure
{
    import std.traits : Unqual;
    return cast(TICache!(Unqual!T))new TWholeCache!T(cont);
}

/** buf の先頭が needles のうちのどれかで始まる場合はそれを取り除く。

Returns:
  buf が needles で始まらなかった場合は 0、
  needles のうちのどれかで始まる場合は、1始まりのインデックスが返る。
**/
int peekPop(T)(TICache!T buf, immutable(T)[][] needles ...)
{
    foreach (i, one; needles)
    {
        if (buf.peek(one.length) == one)
        {
            buf.popFront(one.length);
            return cast(int)(i + 1);
        }
    }
    return 0;
}

/** STOPPER によって独自の停止条件を設定できるキャッシュ。

stack を親と共有する。
STOPPER に遭遇した場合に empty = true となる。STOPPERは取り除かれない。
**/
class TPartCache(T) : TICache!T
{
    protected TICache!T _parent;
    protected const immutable(U)[] STOPPER;
    protected bool _empty;

    ///
    @trusted
    this(TICache!T c, immutable(U)[] s)
    { assert(0 < s.length); _parent = c; STOPPER = s; empty; }

    bool empty() @property @trusted
    {
        if (!_empty)
            _empty = _parent.empty || STOPPER == _parent.peek(STOPPER.length);
        return _empty;
    }

    @property
    U front() { return _empty ? '\0' : _parent.front; }

    @property
    const(U)[] rest() const { return _parent.rest; }

    U popFront(size_t s = 1)
    {
        for (size_t i = 0; i < s && !empty; ++i) _parent.popFront;
        return front;
    }

    const(U)[] peek(size_t s = 1){ return _parent.peek(s); }
    @property
    const(U)[] peekBetter() { return _parent.peekBetter; }
    @trusted @nogc pure const nothrow
    void close(){ }
    U[] read(U[] buf)
    {
        size_t i = 0;
        for (auto f = front; i < buf.length && !_empty ; ++i, f = popFront)
            buf[i] = f;

        return buf[0..i];
    }

    void discard(long s){ popFront(cast(size_t)s); }
    U push(size_t s = 1)
    {
        for (size_t i = 0; i < s && !empty; ++i) _parent.push;
        return front;
    }
    U push(U c)
    {
        if (!empty) _parent.push(c);
        return front;
    }

    @property
    {
        const(U)[] stack() const { return _parent.stack; }
        immutable(U)[] istack() const { return _parent.istack; }

        TPartCache save() const
        { return new TPartCache(cast(TICache!T)_parent.save, STOPPER); }

        ulong tell() const { return _parent.tell; }
        string name() const { return "STOPPABLE CACHE"; }
        const(U)[] dump(){ return _parent.dump; }
        debug Benchmark getBenchmark() const { return Benchmark(); }
    }
    void flush(){ _parent.flush; }

    /// 全部飛ばす。
    void popAll(STRIP S = STRIP.STRICT)()
    {
        for (; !_empty;) popFront;

        static if (S != STRIP.NONE)
        {
            if (0 == _parent.peekPop(STOPPER))
            {
                static if (S == STRIP.STRICT)
                    debug throw new Exception("NO ENDING BRACKET : `"
                                              ~ STOPPER ~ "'.");
            }
        }
    }
}

///
enum STRIP
{
    NONE,   ///
    STRICT, ///
    LOOSE,  ///
}

/** TPartCache を使って部分読み込み。

dg に渡される TICache と parent はスタックが同一なので注意。
dg の実行前後に flush が実行される。
**/
@trusted
U enterPart(T, STRIP S, U)
    (TICache!T parent, immutable(T)[] stopper,
     scope U delegate(TICache!T) dg, bool strong = true)
{
    auto p = parent;
    if (strong) if (auto pt = cast(TPartCache!T)parent) p = pt._parent;

//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
//
// BUG
// ctfe 時に scope auto 変数を使うと dmd が abnormal termination。
// (dmd2.068.2)
    if (__ctfe)
    {
        /*scope*/ auto pc = new TPartCache!T(p, stopper);

        parent.flush;
        static if (is(U == void)) dg(pc);
        else auto v = dg(pc);
        parent.flush;

        pc.popAll!S;

        static if (is(U == void)) return;
        else return v;
    }
    else
    {
        scope auto pc = new TPartCache!T(p, stopper);

        parent.flush;
        static if (is(U == void)) dg(pc);
        else auto v = dg(pc);
        parent.flush;

        pc.popAll!S;

        static if (is(U == void)) return;
        else return v;
    }
};

//------------------------------------------------------------------------------
/** ダブルクォートで終わる文字列のパースに。

以下では、初期化に利用した TICache を 元のTICache と呼ぶ。

popFront などで元のTICache は編集される。
終了ダブルクォートに遭遇すると、empty = true となる。
size とか peek とかは終了ダブルクォート以降も読み取ってしまう。
front / push ではバックスラッシュは取り除かれる。
peek ではバックスラッシュは取り除かれない。
**/
class TQStringCache(T) : TPartCache!T
{
    ///
    @trusted
    this(TICache!T b, immutable(U)[] s = "\"") { super(b, s); }


    override U front() @property
    {
        if (_empty) return '\0';
        if ('\\' == _parent.front)
        {
            auto s = _parent.peek(2);
            if (1 < s.length)
            {
                switch(s[1])
                {
                    case 'n': return '\n';
                    case 't': return '\t';
                    default: return s[1];
                }
            }
            else return '\0';
        }
        return _parent.front;
    }

    override U popFront(size_t s = 1)
    {
        for (size_t i = 0; i < s && !empty; ++i)
        {
            if ('\\' == _parent.front) _parent.popFront(2);
            else _parent.popFront;
        }
        return front;
    }

    alias push = TPartCache!T.push;
    override U push(size_t s = 1)
    {
        for (size_t i = 0; i < s && !empty; ++i)
        {
            if ('\\' == _parent.front) _parent.popFront;
            _parent.push;
        }
        return front;
    }
}

/** 文字列のパースに入る。

Throws:
  終了クォートがなかった場合は Exception を投げる。
**/
@trusted
U enterString(T, U)(TICache!T parent, immutable(T)[] stopper,
                    scope U delegate(TICache!T) dg, bool strong = true)
{
    assert(stopper == parent.peek(stopper.length));
    parent.popFront(stopper.length);

    auto p = parent;
    if (strong) if (auto pt = cast(TPartCache!T)parent) p = pt._parent;

//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// BUG
//
    if (__ctfe)
    {
        auto sc = new TQStringCache!T(p, stopper);

        parent.flush;
        static if (is(U == void)) dg(sc);
        else auto v = dg(sc);
        parent.flush;

        sc.popAll;

        static if (is(U == void)) return;
        else return v;
    }
    else
    {
        scope auto sc = new TQStringCache!T(p, stopper);

        parent.flush;
        static if (is(U == void)) dg(sc);
        else auto v = dg(sc);
        parent.flush;

        sc.popAll;

        static if (is(U == void)) return;
        else return v;
    }
}

//------------------------------------------------------------------------------
// some utils for string.
import std.traits : isSomeChar;

/** 左側の空白文字を切り取る。

std.ascii.isWhite でチェックしている。
**/
void stripLeftWhite(T)(TICache!T buf) if (isSomeChar!T)
{
    import std.ascii : isWhite;
    for (auto c = buf.front; c.isWhite; c = buf.popFront) {}
}

/// pred が true になるまで切り取る。
immutable(T)[] munchUntil(alias pred, T)(TICache!T buf) if (isSomeChar!T)
{
    import std.functional : unaryFun;
    for (auto a = buf.front; !buf.empty; a = buf.push)
        if (a.unaryFun!pred) break;
    auto ret = buf.istack;
    buf.flush;
    return ret;
}

/// 文字列を切り取る。
immutable(T)[] munchString(dstring BRA = "\"'`", T)(TICache!T buf)
    if (isSomeChar!T)
{
    import std.exception : enforce;
    T end;
    immutable(T)[] result;
    foreach (c; BRA){ if (c == buf.front) end = buf.front; }

    if (end == char.init) return result;

    for (buf.popFront; !buf.empty; buf.push)
    {
        if     (end == buf.front)
        {
            result = buf.istack;
            buf.flush;
            buf.popFront;
            break;
        }
        else if ('\\' == buf.front) buf.push;
    }
    (0 < result.length || 0 == buf.stack.length).
        enforce("unterminated string.");
    return result;
}

/// 見つけた needle の終端まで buf を進める。
bool findSkip(T)(TICache!T buf, const(T)[] needle) if (isSomeChar!T)
{
    if (0 == needle.length) return false;
    for (;!buf.empty;buf.popFront)
    {
        if (needle[0] == buf.front && needle == buf.peek(needle.length))
        {
            buf.popFront(needle.length);
            return true;
        }
    }
    return false;
}
/// ditto
bool findSkip(T)(TICache!T buf, T needle) if (isSomeChar!T)
{
    for (;!buf.empty;buf.popFront)
    {
        if (needle == buf.front)
        {
            buf.popFront;
            return true;
        }
    }
    return false;
}


/** buf からの切り出しと変換。

まず、pred が true になるまで buf を読み飛ばし、
pred が true の間、buf を切り出し、std.conv.to で U へと変換する。
**/
U munchAs(U, alias pred, T)(TICache!T buf)
    if (isSomeChar!T)
{
    import std.functional: unaryFun;
    import std.conv : to;

    U ret;
    for (auto a = buf.front; !buf.empty; a = buf.popFront)
        if (a.unaryFun!pred) break;
    for (auto a = buf.front; !buf.empty; a = buf.push)
        if (!a.unaryFun!pred) break;
    auto stack = buf.stack;
    if (0 < stack.length) ret = stack.to!U;
    buf.flush;
    return ret;
}

/// ditto
U[] munchAsMuch(U, alias pred, alias stopper = "false", T)(TICache!T buf)
    if (isSomeChar!T)
{
    import std.functional: unaryFun;
    import std.conv : to;
    import std.array : Appender;

    Appender!(U[]) ret;
    outer: for (; !buf.empty;)
    {
        for (auto a = buf.front; !buf.empty; a = buf.popFront)
        {
            if      (a.unaryFun!stopper) break outer;
            else if (a.unaryFun!pred) break;
        }
        for (auto a = buf.front; !buf.empty; a = buf.push)
            if (!a.unaryFun!pred) break;
        auto stack = buf.stack;
        if (0 < stack.length) ret.put(stack.to!U);
        buf.flush;
    }
    return ret.data;
}

/** 文字列を整数にする。
str 先頭から数字ではない文字を取り除き、
(.(ピリオド)、_(アンダースコア)も数字ではないとする)整数を得る。
**/
int toLONG(T)(TICache!T buf) if (isSomeChar!T)
{
    int negative = 1;
    for (auto a = buf.front; !buf.empty; a = buf.popFront)
    {
        if      (a == '-') { negative = -1; break; }
        else if ('0' <= a && a <= '9') break;
    }

    return buf.munchAs!(int, q{'0' <= a && a <= '9'}) * negative;
 }


/** 文字列を整数の配列にする。
str 先頭から数字ではない文字を区切りとし
(.(ピリオド)、_(アンダースコア)も区切りとする)、size 個の整数を得る。
**/
int[] toLONGS(T)(TICache!T buf, size_t size) if (isSomeChar!T)
{
    auto rc = new int[size];
    for (size_t i = 0; i < size; ++i) rc[i] = buf.toLONG;
    return rc;
}

/// 整数を読み取りながら buf の最後まで進める。
int[] toLONGSasMuch(T)(TICache!T buf)
{
    import std.array : Appender;
    Appender!(int[]) app;
    for (; !buf.empty; ) app.put(buf.toLONG);
    return app.data;
}

///
void fillLONGS(T, size_t V)(TICache!T buf, out int[V] o) if (isSomeChar!T)
{
    for (size_t i = 0; i < V; ++i)
        o[i] = buf.munchAs!(int, q{'0' <= a && a <= '9' || ('-' == a)});
}


/// ditto
U toLONGSas(U, T)(TICache!T buf)
    if (isSomeChar!T && is(U == struct))
{
    U u;
    foreach (one; __traits(derivedMembers, U))
    {
        static if (is(typeof(__traits(getMember, U, one)) : int))
            __traits(getMember, u, one) =
                buf.munchAs!(int, q{'0' <= a && a <= '9' || '-' == a});
    }
    return u;
}

/// std.ascii.isAlphaNum が true を返す間、切り出す。
immutable(T)[] toWORD(T)(TICache!T buf) if (isSomeChar!T)
{
    import std.ascii : isAlphaNum;
    return buf.munchAs!(immutable(T)[], isAlphaNum);
}

/** 文字列から浮動小数点数に。CTFEコンパチ。

Params:
  PUSH = true では、buf.stack にパースした文字列が入る。

Bugs:
  桁あふれとか桁落ちとか考慮してません。
**/
real toFloating(T)(TICache!T buf)
{
    import std.traits : Unqual;
    alias U = Unqual!T;
    real minus = 1;
    bool hasPoint = false;
    real point = 1;
    real value = 0;
    real exp = 1;
    U c;

    for (c = buf.front; !buf.empty; c = buf.popFront)
    {
        if      (c == '_') continue;
        else if (c == '-') minus = -1;
        else if (c == '.') hasPoint = true;
        else if ('0' <= c && c <= '9')
        {
            value = value * 10 + (c - '0');
            if (hasPoint) point *= 0.1;
        }
        else break;
    }

    if (c == 'e' || c == 'E')
    {
        bool isMinus = false;
        int e = 0;
        for (; !buf.empty;)
        {
            c = buf.popFront;
            if      (c == '_') continue;
            else if (c == '-') isMinus = true;
            else if ('0' <= c && c <= '9')
                e = e * 10 + (c - '0');
            else break;
        }
        if (isMinus)
            for (size_t i = 0; i < e; ++i) exp *= 0.1;
        else
            for (size_t i = 0; i < e; ++i) exp *= 10;
    }
    return minus * value * point * exp;
}


/// 先頭の不要物を飛ばして浮動小数点数を一つ切り出す。
real munchFloating(T)(TICache!T buf)
{
    for (auto c = buf.front; !buf.empty; c = buf.popFront)
    {
        if (c == '-' || c == '.' || ('0' <= c && c <= '9')) break;
    }
    return buf.toFloating;
}

///
void munchFloatingToFill(T, U)(TICache!T buf, U[] o)
    if (is(U : real))
{
    for (size_t i = 0; i < o.length; ++i)
        o[i] = buf.munchFloating;
}

///
void munchFloatingToFill(U, T)(TICache!T buf, out U o)
    if (isSomeChar!T && is(U == struct))
{
    foreach (one; __traits(derivedMembers, U))
    {
        static if (is(typeof(__traits(getMember, U, one).offsetof)))
            static if (is(typeof(__traits(getMember, U, one)) : real))
                __traits(getMember, o, one) = buf.munchFloating;
    }
}

/// big endian でバイナリデータを読み出す。
void munchBinaryToFill(T, U)(TIReadSeq!T buf, out U o)
    if (T.sizeof == 1 && (!is(U : V[], V)))
{
    template isValid(V)
    {
        static if      (is(V : W[N], W, size_t N) && isValid!W)
            enum isValid = true;
        else static if (is(V : W[], W))
            enum isValid = false;
        else static if (is(V == struct) || __traits(isPOD, V))
            enum isValid = true;
        else
            enum isValid = false;
    }


    static if      (is(U == struct))
    {
        foreach (one; __traits(derivedMembers, U))
            static if (isMemberVariable!(U, one) &&
                       isValid!(typeof(__traits(getMember, U, one))))
                buf.munchBinaryToFill(__traits(getMember, o, one));
    }
    else static if (__traits(isPOD, U))
    {
        import std.bitmanip : bigEndianToNative;
        import std.exception : enforce;
        ubyte[U.sizeof] b;
        enforce(U.sizeof == buf.read(b).length);
        static if      (U.sizeof == 1)
            o = b[0];
        else static if (U.sizeof == 2)
            o = cast(U)b.bigEndianToNative!ushort;
        else static if (U.sizeof == 4)
            o = cast(U)b.bigEndianToNative!uint;
        else static assert(0);
    }
    else static assert(0);
}

///
void munchBinaryToFill(T, U)(TIReadSeq!T buf, U[] o) if (T.sizeof == 1)
{
    foreach (ref one; o)
        buf.munchBinaryToFill(one);
}


//==============================================================================
//##############################################################################
//
// private
//
//##############################################################################
//==============================================================================
//------------------------------------------------------------------------------
debug struct Benchmark
{
    size_t refill_times = 0;
    float use_max = 0.0;
    float use_average = 0.0;
    size_t rest_max_time = 0;
    float rest_max = 0.0;
    float rest_average = 0.0;
}

//------------------------------------------------------------------------------
// メモリのコピーに。
@trusted @nogc pure nothrow
private void _array_copy_to(T)(in T[] src, T[] dest)
{
    assert(src.length <= dest.length);

    if     (0 == src.length || src.ptr == dest.ptr) { }
    else if (dest.ptr + src.length <= src.ptr
           || src.ptr + src.length <= dest.ptr)
    {
        dest[0 .. src.length] = src;
    }
    else if (dest.ptr < src.ptr)
    {
        for (size_t i = 0 ; i < src.length ; i++) dest[i] = src[i];
    }
    else if (src.ptr < dest.ptr)
    {
        for (size_t i = 0 ; i < src.length ; i++)
            dest[src.length-i-1] = src[$-i-1];
    }
}

//------------------------------------------------------------------------------
// スライスの操作に
private class SliceMaker(T)
{
    import std.traits : Unqual;

    public T[] _payload;
    alias _payload this;

    @trusted @nogc pure nothrow
    this(T[] v){ this._payload = v; }

    @trusted pure nothrow
    {
        Slice slice() { return new Slice(0, 0);}
        Slice slice(size_t i)
        { assert(i <= _payload.length); return new Slice(i, i); }
        Slice slice(size_t i, size_t j)
        {
            assert(i <= j);
            assert(j <= _payload.length);
            return new Slice(i, j);
        }
        auto sliceAll() const { return new const Slice(0, _payload.length); }

        @property
        SliceMaker dup() const { return new SliceMaker(_payload.dup); }
    }

    class Slice
    {
        private size_t _head, _tail;

        @trusted @nogc pure nothrow
        this(size_t h, size_t t) { _head = h; _tail = t; }

        @property @trusted @nogc pure nothrow
        {
            T* ptr() { return _payload.ptr + _head; }
            const(T)* ptr() const { return _payload.ptr + _head; }
            size_t length() const { return _tail - _head; }
            size_t head() const { return _head; }
            size_t tail() const { return _tail; }
            void head(size_t p) { assert(p <= _tail); _head = p; }
            void tail(size_t p)
            { assert(p <= _payload.length); assert(_head <= p); _tail = p; }
            T* tailPtr() { return _payload.ptr + _tail; }
            const(T)* tailPtr() const { return _payload.ptr + _tail; }
            T[] payload() { return _payload; }
            bool empty() const { return _tail <= _head; }
            T front() const
            { return _head < _tail ? _payload[_head] : T.init; }
        }
        @trusted @nogc pure nothrow
        {
            void set(size_t h)
            {
                assert(h <= _payload.length);
                _head = _tail = h;
            }
            void set(size_t h, size_t t)
            {
                assert(t <= _payload.length);
                assert(h <= t);
                _head = h; _tail = t;
            }
            void clear(size_t pos = 0)
            {
                assert(pos <= _payload.length);
                _head = _tail = pos;
            }
            T popFront(size_t n = 1)
            {
                if (_head + n < _tail){ _head += n; return _payload[_head]; }
                else { _head = _tail; return T.init; }
            }

            T opIndex(size_t i) const
            {
                assert(_head + i < _tail);
                return _payload[_head + i];
            }
            static if (!is(T == const) && !is(T == immutable))
            {
                void opIndexAssign(T value, size_t i)
                {
                    assert(_head + i < _tail);
                    _payload[_head + i] = value;
                }
            }
            T[] opSlice() { return _payload[_head .. _tail]; }
            T[] opSlice(size_t i, size_t j)
            {
                assert(i <= j);
                assert(_head + j <= _tail);
                return _payload[_head + i .. _head + j];
            }
            const(T)[] opSlice() const { return _payload[_head .. _tail]; }
            const(T)[] opSlice(size_t i, size_t j) const
            {
                assert(i <= j);
                assert(_head + j <= _tail);
                return _payload[_head + i .. _head + j];
            }

            inout(Unqual!T)[] apply(inout(Unqual!T)[] arr) const
            { return arr[_head .. _tail]; }

            void growBack(size_t n = 1)
            {
                if (_tail + n < _payload.length) _tail += n;
                else _tail = _payload.length;
            }
            static if (!is(T == const) && !is(T == immutable))
            {
                void pushBack(in T[] src ...)
                {
                    assert(_tail + src.length <= _payload.length);
                    _array_copy_to(src, _payload[_tail .. _tail + src.length]);
                    _tail = _tail + src.length;
                }
            }
        }
    }
}

//------------------------------------------------------------------------------
// sugar
@trusted @nogc pure nothrow private
{
    void copyTo(T)(SliceMaker!T.Slice src, T[] dest)
    { _array_copy_to(src[], dest); }
    void copyTo(T)(SliceMaker!T.Slice src, SliceMaker!T.Slice dest)
    { _array_copy_to(src[], dest[]); }
    void moveTo(T)(SliceMaker!T.Slice src, size_t dest)
    {
        _array_copy_to(src[], src.payload[dest .. $]);
        src.set(dest, dest + src.length);
    }
}

////////////////////XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\\\\\\\\\\\\\\\\\\\\
//
// DEBUG
//
debug(cached_buffer):
import std.ascii, std.utf;
import sworks.base.output;
import sworks.base.dump_members;
import std.stdio;

string func(TICache!char buf)
{
    float[2] f;
    buf.munchFloatingToFill(f);
    return buf.rest.idup;
}


void main()
{
    enum f = "M 383.85795,376.06506 A 101.52033,85.357887 0 0 1 282.33762,290.7
0717 Z".toCache.func;
    f.writeln;
}
