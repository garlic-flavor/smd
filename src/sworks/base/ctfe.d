/** class 以外を初期化文字列に。
 */
module sworks.base.ctfe;
import std.traits;

/// float から小数点以下が PREC ケタの文字列へ。
@trusted pure nothrow
string toFixedPointString(int PREC)(in real r)
{
    import std.conv : to;
    import std.string : join;

    enum e = 10 ^^ PREC;
    auto ir = cast(ulong)(r * e);

    auto fs = (ir%e).to!string;
    auto result = [(ir/e).to!string, "."];
    for (size_t i = fs.length; i < PREC; ++i) result ~= "0";
    result ~= fs;
    return result.join;
}

///
@trusted pure nothrow
string toInitializer(T)(in T v) if (isFloatingPoint!T)
{ return v.toFixedPointString!8; }

/// ditto
pure
string toInitializer(T)(in T v)
    if (is(T : bool) || isIntegral!T && !is(T == enum))
{ return v.to!string; }

/// ditto
pure
string toInitializer(T)(in const(T)[] v) if (isSomeChar!T)
{
    import std.exception : assumeUnique;
    auto c = new char[v.length+2];
    c[0] = c[$-1] = '"';
    c[1..$-1] = v;
    return c.assumeUnique;
}

/// ditto
pure
string toInitializer(T)(in T[] v) if (!isSomeChar!T)
{
    import std.string : join;

    auto ini = new string[v.length];
    for (size_t i = 0; i < ini.length; ++i)
        ini[i] = v[i].toInitializer;
    return 0 < ini.length ? ["[" , ini.join(","), "]"].join : "null";
}

/// ditto
pure
string toInitializer(T : U[V], U, V)(in T p)
{
    import std.string : join;

    auto vs = p.values;
    auto ini = new string[vs.length];
    size_t i = 0;
    foreach (key, one; p)
    {
        ini[i] = [key.toInitializer, ":", one.toInitializer].join;
        ++i;
    }
    return 0 < ini.length ? ["[", ini.join(","), "]"].join : "null";
}

/// ditto
pure
string toInitializer(T)(in auto ref T v) if (is(T == struct))
{
    import std.string : join;
    auto ini = new string[FieldNameTuple!T.length];
    size_t i = 0;
    foreach (one; FieldNameTuple!T)
        ini[i++] = __traits(getMember, v, one).toInitializer;
    return [fullyQualifiedName!T, "(", ini.join(","), ")"].join;;
}

/// ditto
pure
string toInitializer(T)(in T v) if (is(T == enum))
{ return [fullyQualifiedName!T, ".", v.to!string].join; }


////////////////////XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX\\\\\\\\\\\\\\\\\\\\
debug(ctfe):

import std.stdio;
struct Test
{
    enum TYPE
    {
        DUMMY,
        PSEUDO,
    }
    int x;
    float y;
    string[] z;
    TYPE t;
    int[string] u;
}

void main()
{
    enum t = Test(1, 0.5, ["hoge", "fuga"], Test.TYPE.PSEUDO, ["moga":1]);
    auto t1 = mixin(t.toInitializer);
    assert(t == t1);
}
