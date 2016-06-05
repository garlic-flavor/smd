/** I/O の抽象化。
 * Version:    0.0001(dmd2.071.0)
 * Date:       2016-Jan-31 18:40:43
 * Authors:    KUMA
 * License:    CC0
 */
/**
 * Description:
 *   ファイル入出力を抽象化する。$(BR)
 *   インスタンスをそれぞれの機能を表現したインターフェイスへと実行時キャスト
 *   することで利用する。$(BR)
 *   サイズや現在位置を示すのに、byteではなく「要素数」を使うので注意。
 */
module sworks.base.aio;

//==============================================================================
//
// インターフェイス
//
//==============================================================================
/// IO の元となるインターフェイス
interface IAIO
{
    import std.traits : Unqual;
    void close(); ///
    string name() const; ///
    bool empty(); ///
}

//------------------------------------------------------------------------------
/// サイズが分かっている
interface TIKnownSize(T)
{
    /// 全体の要素数。
    ulong size();
}

//------------------------------------------------------------------------------
/// 現在位置を保持している。
interface ITell(T)
{
    /// 現在位置。単位は要素量。
    ulong tell() const;
}
//------------------------------------------------------------------------------
/// 逐次読み込みに対応している。
interface TIReadSeq(T) : IAIO, ITell!T
{
    /// buf を値で埋める。実際に埋められた分をスライスで返す。
    /// 読んだ分だけ現在位置が進む。
    Unqual!T[] read(Unqual!T[] buf);

    /// 現在位置から s 要素分進める。
    /// バイト数ではない。
    void discard(long s);
}
/// ditto
alias IReadSeq = TIReadSeq!ubyte;

//------------------------------------------------------------------------------
/// シークに対応している。
interface TIRandomAccess(T) : IAIO, TIKnownSize!T
{
    /// 現在位置から s 要素分移動する。
    /// バイト数ではない。
    void seek(long s);

    /// s の単位は要素数
    void seekSet(long s);
    /// ditto
    void seekEnd(long s);
}
/// ditto
alias IRandomAccess = TIRandomAccess!ubyte;

//------------------------------------------------------------------------------
/// 逐次書き出しに対応している。
interface TIWrite(T) : IAIO
{
    ///
    void write(in Unqual!T[] buf);
}
/// ditto
alias IWrite = TIWrite!ubyte;

//------------------------------------------------------------------------------
/// 現在の状態を保存する。
interface ISave
{
    ///
    ISave save() const;
}

//------------------------------------------------------------------------------
/// forward range
interface IForwardRange(T)
{
    import std.traits : Unqual;
    ///
    Unqual!T front();
    /// s 要素分カーソルを進めて次の要素を返す。
    Unqual!T popFront(size_t s = 1);
}

/// peekable range
interface IPeekRange(T) : IForwardRange!T
{
    /// バッファの先頭 s 要素分を読み取るが、カーソルは進めない。
    const(Unqual!T)[] peek(size_t s);
    /** 現在キャッシュしてる分だけ、とか、メモリコピーのなるべく発生しない
     * 方法で読める分だけ読み取る。
     */
    const(Unqual!T)[] peekBetter();
}

//==============================================================================
//
// 実装
//
//==============================================================================
/// std.stdio.File による実装
class TFileIO(T) : TIReadSeq!T, TIRandomAccess!T, TIWrite!T, ISave
{
    import std.stdio : File, SEEK_CUR, SEEK_SET, SEEK_END;
    private File _payload;

    ///
    this(string filename, string mode = "rb")
    { _payload = File(filename, mode); }

    void close(){ _payload.close; }
    string name() const { return _payload.name; }
    bool empty() const { return _payload.eof; }
    ulong size() { return _payload.size / T.sizeof; }
    Unqual!T[] read(Unqual!T[] buf) { return _payload.rawRead(buf); }
    void discard(long s){ _payload.seek(s * T.sizeof, SEEK_CUR); }
    ulong tell() const { return _payload.tell / T.sizeof; }

    void seek(long s){ _payload.seek(s * T.sizeof, SEEK_CUR); }
    void seekSet(long s){ _payload.seek(s * T.sizeof, SEEK_SET); }
    void seekEnd(long s){ _payload.seek(s * T.sizeof, SEEK_END); }

    void write(in Unqual!T[] buf){ _payload.rawWrite(buf); }

    TSavedFileIO!T save() const
    { return new TSavedFileIO!T(name, tell, "rb"); }
}
/// ditto
alias FileIO = TFileIO!ubyte;

//------------------------------------------------------------------------------
/// TFileIO.save の戻り値
class TSavedFileIO(T) : TIReadSeq!T, TIRandomAccess!T, ISave
{
    import std.stdio : File, SEEK_CUR, SEEK_SET, SEEK_END;
    private File _payload;
    private string _filename, _mode;
    private ulong _pos;

    //
    private this(string filename, ulong pos, string mode = "rb")
    {
        _filename = filename;
        _pos = pos;
        _mode = mode;
    }

    private void open()
    {
        if (!_payload.isOpen)
        {
            _payload = File(_filename, _mode);
            _payload.seek(_pos * T.sizeof);
        }
    }

    void close(){ _payload.close; }
    string name() const { return _filename; }
    bool empty() const { return _payload.eof; }

    ulong size() { open; return _payload.size / T.sizeof; }

    Unqual!T[] read(Unqual!T[] buf){ open; return _payload.rawRead(buf); }
    void discard(long s)
    {
        if (_payload.isOpen)
            _payload.seek(s * T.sizeof, SEEK_CUR);
        else
            _pos += s;
    }

    ulong tell() const
    {
        if (_payload.isOpen)
            return _payload.tell / T.sizeof;
        else
            return _pos;
    }

    void seek(long s)
    {
        if (_payload.isOpen)
            _payload.seek(s * T.sizeof, SEEK_CUR);
        else
            _pos += s;
    }
    void seekSet(long s)
    {
        if (_payload.isOpen)
            _payload.seek(s * T.sizeof, SEEK_SET);
        else
            _pos = s;
    }
    void seekEnd(long s){ open; _payload.seek(s * T.sizeof, SEEK_END); }

    TSavedFileIO save() const
    { return new TSavedFileIO(_filename, tell, _mode); }
}

//------------------------------------------------------------------------------
/// array による実装。
class TMemIO(T) : TIReadSeq!T, TIRandomAccess!T, ISave
{
    alias U = Unqual!T;
    private T[] _payload;
    private T[] _rest;

    ///
    this(T[] buf){ _payload = buf; _rest = _payload;}

    private this(T[] p, size_t r)
    { _payload = p; _rest = _payload[$-r..$]; }

    void close() { _payload = null; }
    string name() const { return T.stringof; }
    bool empty() const { return 0 == _rest.length; }
    ulong size() const { return _payload.length; }

    U[] read(U[] buf)
    {
        auto l = _rest.length < buf.length ? _rest.length : _buf.length;
        _buf[0..l] = _rest[0..l];
        _rest = _rest[l..$];
        return _buf[0..l];
    }
    void discard(long s)
    {
        auto p = _payload.length - _rest.length + s;
        if      (p < 0) p = 0;
        else if (_payload.length < p) p = _payload.length;
        _rest = _payload[p..$];
    }
    ulong tell() const { return _payload.length - _rest.length; }

    void seek(long s)
    {
        auto p = _payload.length - _rest.length + s;
        if      (p < 0) p = 0;
        else if (_payload.length < p) p = _payload.length;
        _rest = _payload[p..$];
    }
    void seekSet(long s){ _rest = _payload[cast(size_t)s .. $]; }
    void seekEnd(long s){ _rest = _payload[(cast(size_t)$+s) .. $]; }

    TMeMIO save() const
    { return new TMeMIO(_payload, rest.length); }
}

//------------------------------------------------------------------------------
/// suger。とりあえず全部読む。
T[] TreadAll(T)(IAIO io)
{
    import std.conv : to;
    import std.exception : enforce;
    auto buf = new T[io.to!(TIKnownSize!T).size.to!size_t];
    (io.to!(TIReadSeq!T).read(buf).length == buf.length).enforce;
    return buf;
}
/// ditto
alias readAll = TreadAll!ubyte;
