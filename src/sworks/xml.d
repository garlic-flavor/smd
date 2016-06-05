/** なんちゃってXMLパーサ。CTFEコンパチ。
Date:       2016-Apr-17 23:17:01
Authors:    KUMA
License:    CC0

Bugs:
CTFE時には、Ns.uri 及び Ns.ns はnull。
これは CTFE 時に toHash/toEquals が呼び出されないから。

dmd2.068.2
$(OL
$(LI std.typecos.Rebindable doesn't work at CTFE.)
$(LI An AA doesn't execute toHash/opEquals at CTFE.)
$(LI A lambda expression miss its outer environment at CTFE.)
)

compile_to_do_unittest:
> dmd -Isrc -debug -debug=BUGCHECK_4 -unittest -main src\sworks\xml.d .\src\sworks\base\aio.d .\src\sworks\util\cached_buffer.d .\src\sworks\base\ctfe.d;./xml.exe

**/

module sworks.xml;

import sworks.util.cached_buffer;
import sworks.base.ctfe;
debug import std.stdio : writeln;


//==============================================================================
/// XML 構造を表現するルートクラス
abstract class AXML
{
    /// XML文字列を返す。
    @property @trusted pure abstract override
    string toString() const;

    /// deep duplication
    @property @trusted
    abstract AXML dup() const;

    /// 登場順に要素を巡回する。
    int opApply(scope int delegate(AXML) dg)
    { return dg(this); }

    /// ditto
    int opApply(scope int delegate(in AXML) dg) const
    { return dg(this); }
}

/// 中身の文字列
class XMLText : AXML
{
    /// 中身
    string text;
    ///
    @trusted @nogc pure nothrow
    this(string t) { text = t; }

    //
    @property @trusted pure nothrow override
    string toString() const { return text; }
    //
    @property @trusted pure nothrow override
    XMLText dup() const { return new XMLText(text); }
}

/// 要素。
class XML : AXML
{
    /// 要素の名前
    /// XML_PARSER_PROPERTY.LOWER_CASE では全て小文字で格納される。
    Ns name;
    /// 属性
    Attribute attr;
    /// 子要素
    AXML[] children;

    ///
    @trusted @nogc pure nothrow
    this() const { }
    ///
    @trusted @nogc pure nothrow
    this(in Ns n) { name = n; }
    ///
    @trusted @nogc pure nothrow
    this(in Ns n, Attribute a, AXML[] c = null)
    { name = n; attr = a; children = c; }

    //
    @property @trusted
    override XML dup() const
    { return new XML(name, attr.dup, dupChildren); }

    @property @trusted
    AXML[] dupChildren() const
    {
        auto nc = new AXML[children.length];
        for (size_t i = 0; i < children.length; ++i) nc[i] = children[i].dup;
        return nc;
    }

    /// 登場順に要素を巡回する。
    @trusted override
    int opApply(scope int delegate(AXML) dg)
    {
        auto result = dg(this);
        if (result) return result;
        for (size_t i = 0; i < children.length; ++i)
        {
            result = children[i].opApply(dg);
            if (result) break;
        }
        return result;
    }

    /// ditto
    @trusted override
    int opApply(scope int delegate(in AXML) dg) const
    {
        auto result = dg(this);
        if (result) return result;
        for (size_t i = 0; i < children.length; ++i)
        {
            result = children[i].opApply(dg);
            if (result) break;
        }
        return result;
    }

    //
    @property @trusted pure override
    string toString() const
    {
        import std.string : join;
        if (0 < children.length)
        {
            auto buf = new string[children.length+2];
            auto n = name.toString;
            buf[0] = ["<", n, " ", attr.toString, ">"].join;
            buf[$-1] = ["</", n, ">"].join;
            foreach (i, child; children) buf[i+1] = child.toString;
            return buf.join("\n");
        }
        else
            return ["<", name.toString, " ", attr.toString, " />"].join;
    }

    //
    @property @trusted pure nothrow private
    string getOpenTagString()
    { import std.string : join; return ["<", name.toString, ">"].join; }
}

//------------------------------------------------------------------------------
//
/// 要素内で最初に出てくる文字列を返す。
@trusted
string searchText(in AXML tag)
{
    if (tag is null) return null;
    foreach (t; tag)
        if (auto tt = cast(XMLText)t) return tt.text;
    return null;
}

/// 要素内に含まれる全ての文字列を返す。
@trusted
string[] searchAllText(in AXML tag)
{
    if (tag is null) return null;
    import std.array : Appender;
    Appender!(string[]) buf;
    foreach (t; tag)
        if (auto tt = cast(XMLText)t) buf.put(tt.text);
    return buf.data;
}

//------------------------------------------------------------------------------
/** 名前空間つきのん。

$(UL 
  $(LI opEquals に関して、$(BR)
    オペランドの両方の uri がある場合、
    value と uri の両方が一致したときに true。$(BR)
    オペランドの少なくとも一方の uri がない場合、
    value が一致したときに true。$(BR)
    名前空間名に関しては比較してません。
)

  $(LI toHash に関して。$(BR)
    hash値は core.internal.hashOf(value) の値を使っています。$(BR)
    uri や、ns はhash値に影響しません。$(BR)
)
)
**/
struct Ns
{
    string value; /// 名前空間名を含まない。
    alias value this;

    string uri;  /// ネームスペースの参照先のURI
    string ns;   /// 名前空間名

    @trusted @nogc pure nothrow
    {
        ///
        @property
        bool empty() const { return 0 == value.length; }

        ///
        bool opEquals(in string r) const { return value == r; }
        ///
        bool opEquals(in ref Ns r) const
        {
            return value == r.value && (r.uri.length == 0 || uri.length == 0
                                                          || uri == r.uri);
        }
    }
    /// value の hash を取る。(uriとnsは無関係)
    @property @trusted pure nothrow
    size_t toHash() const
    { import core.internal.hash : hashOf; return value.hashOf; }

    ///
    @property @trusted pure nothrow
    string toString() const
    {
        import std.string : join;
        if (0 < ns.length) { return [ns, ":", value].join; }
        else return value;
    }

    ///
    @property @trusted pure nothrow
    string toFullString() const
    {
        import std.string : join;
        return [ns, ":", value, ":", uri].join;
    }
}

/// suger
@trusted @nogc pure nothrow
Ns ns(in string v) { return Ns(v); }

//------------------------------------------------------------------------------
// std.typecons.Rebindable が CTFE できないのでかわり。
struct Rebindable(T) if (is(T == class) || is(T == interface))
{
    import std.traits : Unqual;
    alias U = Unqual!T;

    private U stripped;

    @trusted pure nothrow @nogc
    {
        void opAssign(in U another) { stripped = cast(U)another; }
        void opAssign(typeof(this) another)
        { stripped = cast(U)another.stripped; }
        this(in U v){ opAssign(v); }
        ref inout(U) get() inout { return stripped; }
    }
    alias get this;
}


/** 属性

値は std.typecons.Rebindable によって格納されている。
値を変更する場合は新しい AttributeValue インスタンスで上書きすべきで、
取り出した AttributeValue インスタンスの中身を変えるべきでない。

Bugs:
  CTFE 時に問題アリアリ。
  dmd2.068.2
  $(OL
    $(LI std.typecos.Rebindable doesn't work at CTFE.)
    $(LI An AA doesn't execute toHash/opEquals at CTFE.)
)
**/
struct Attribute
{
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// BUG.
    // import std.typecons : Rebindable; // NO CTFE
    private alias A = Rebindable!(const AttributeValue);

    private A[Ns] _payload; // 中身

    ///
    @trusted
    {
        /** shallow copy だが、値が const であることが保証されているため、
         * deep copy 相当
         */
        pure
        Attribute dup() const { return Attribute(cast(A[Ns])_payload.dup); }
        /// 文字列として値を取り出す。
        string opIndex(in Ns nn) const
        {
            if (auto pv = nn in _payload) return (*pv).toString;
            return null;
        }
        /// ditto
        string opIndex(in string nn) const
        {
            if (auto pv = Ns(nn) in _payload) return (*pv).toString;
            return null;
        }
    }

    /// 属性値を合成する。右辺値優先
    @trusted pure
    void overwrite(in ref Attribute r)
    { foreach (key, val; r._payload) _payload[key] = A(val); }

    ///
    @trusted @nogc pure nothrow
    auto opBinaryRight(string OP : "in")(in string n) const
    { return Ns(n) in _payload; }

    /// ditto
    @trusted @nogc pure nothrow
    auto opBinaryRight(string OP : "in")(in Ns nn) const
    { return nn in _payload; }

    @trusted pure nothrow
    {
        /// 属性値を代入する。
        auto opIndexAssign(in AttributeValue v, in Ns nn)
        { _payload[nn] = A(v); return v; }
        /// ditto
        auto opIndexAssign(in AttributeValue v, in string n)
        { _payload[Ns(n)] = A(v); return v; }
    }

    /// 属性値としての文字列を得る。
    @trusted pure
    string toString() const
    {
        import std.array : Appender, join;
        Appender!(string[]) buf;
        foreach (key, one; _payload)
            buf.put([key.toString, "=\"", one.toString, "\""].join);
        return buf.data.join(" ");
    }

    /// CSSの中身っぽい文字列として得る。
    @trusted pure
    string toCSSString() const
    {
        import std.array : Appender, join;
        Appender!(string[]) buf;
        foreach (key, one; _payload)
            buf.put([key.toString, ":", one.toString, ";"].join);
        return buf.data.join(" ");
    }

    @trusted pure
    {
        /// 値の中身(IntValue.valueとか)を得る。
        /// エントリがなかった場合、null ではなく初期値が返るので注意。
        auto get(T = StringValue, U = typeof(T.value))
            (in Ns nn, lazy U def = U.init) const
        {
            static if (is(T == StringValue))
            {
                if (auto pv = nn in _payload) return pv.toString;
                return def;
            }
            else
            {
                if (auto pv = nn in _payload)
                    if (auto v = (cast(const(T))(*pv)))
                        return v.value;
                return def;
            }
        }
        /// ditto
        auto get(T = StringValue, U = typeof(T.value))
            (in string nn, lazy U def = U.init) const
        {
            static if (is(T == StringValue))
            {
                if (auto pv = Ns(nn) in _payload) return pv.toString;
                return def;
            }
            else
            {
                if (auto pv = Ns(nn) in _payload)
                    if (auto v = (cast(const(T))(*pv)))
                        return v.value;
                return def;
            }
        }

        /// const(AttributeValue) 型のインスタンスとして得る。
        /// エントリがなかった場合は null が返る。
        auto getAs(T = AttributeValue)(in Ns nn) const
            if (!is(T == enum))
        {
            if (auto pv = nn in _payload) return cast(const(T))(*pv);
            return null;
        }
        /// ditto
        auto getAs(T = AttributeValue)(in string nn) const
            if (!is(T == enum))
        {
            if (auto pv = Ns(nn) in _payload) return cast(const(T))(*pv);
            return null;
        }

        /** 値を文字列として取り出し、std.conv.to によって enum へと変換する。
         * エントリがなかった場合は enum の初期値が返る。
         */
        T getAs(T)(in string key) const
            if (is(T == enum))
        {
            import std.conv : to;
            import std.string : toUpper;
            if (auto pv = Ns(key) in _payload)
                return pv.toString.toUpper.to!T;
            return T.init;
        }
    }


    /// 属性値を巡回する。
    int opApply(scope int delegate(in AttributeValue) dg) const
    {
        int result = 0;
        foreach (one; _payload)
        {
            result = dg(one);
            if (result) break;
        }
        return result;
    }

    /// ditto
    int opApply(scope int delegate(in Ns, in AttributeValue) dg) const
    {
        int result = 0;
        foreach (key, one; _payload)
        {
            result = dg(key, one.get);
            if (result) break;
        }
        return result;
    }

    ///
    @property pure nothrow
    Ns[] keys() const { return _payload.keys; }
}


//------------------------------------------------------------------------------
/** 属性の値のルートクラス

それぞれの中身の名前を value で統一しておくと、良いことがある。
$(LINK #sworks.xml.Attribute.get)
*/
abstract class AttributeValue
{
    /// 文字列表現
    @property @trusted pure
    ///
    override string toString() const { return null; }
}

///
class AttributeBase(T) : AttributeValue
{
    T value;

    @trusted @nogc pure nothrow
    this(in T v){ value = v; }

    @property @trusted pure
    override string toString() const
    { import std.conv : to; return value.to!string; }
}

///
alias IntValue = AttributeBase!int;
alias UintValue = AttributeBase!uint;
alias StringValue = AttributeBase!string;

///
class FloatValue : AttributeValue
{
    ///
    float value;
    ///
    @trusted @nogc pure nothrow
    this(in float v) { value = v; }

    /// $(LINK #sworks.base.ctfe.toFixefPointString)を使っているので注意。
    @property @trusted pure nothrow
    override string toString() const
    { return value.toFixedPointString!8; }
}

///
class ClassValue : AttributeValue
{
    ///
    string[] value;
    ///
    @trusted @nogc pure nothrow
    this(string[] cs) { value = cs; }

    @property @trusted pure nothrow
    override string toString() const
    { import std.string : join; return value.join(" "); }
}

///
class XMLValue : AttributeValue
{
    const AXML value; ///
    ///
    @trusted @nogc pure nothrow
    this(in AXML v){ value = v; }

    @property @trusted pure
    override string toString() const
    { return value.toString; }
}


///
class ColorValue : UintValue
{
    ///
    @trusted @nogc pure nothrow
    this(in uint v) { super(v); }

    @property @trusted pure nothrow
    override string toString() const
    {
        char[9] buf;
        buf[0] = '#';
        for (size_t i = 0; i < 8; ++i)
        {
            auto b = 0xf & (value >> (i*4));
            if (b < 10) buf[$-i-1] = cast(char)('0' + b);
            else buf[$-i-1] = cast(char)('A' + (b-10));
        }
        return buf.idup;
    }
}

///
class LengthValue : FloatValue
{
    ///
    @trusted @nogc pure nothrow:
    this(in float v) { super(v); }
    ///
    @trusted @nogc pure nothrow
    float toInch(in ref UnitLength ul) const { return value / ul.ppi; }
    ///
    @trusted @nogc pure nothrow
    int toPixel(in ref UnitLength) const { return cast(int)value; }
}

///
class InchValue : LengthValue
{
    ///
    @trusted @nogc pure nothrow:
    this(in float v) { super(v); }
    //
    @trusted @nogc pure nothrow
    override float toInch(in ref UnitLength) const { return value; }
    //
    @trusted @nogc pure nothrow
    override int toPixel(in ref UnitLength ul) const
    { return cast(int)(value * ul.ppi); }
}

///
class EMValue : LengthValue
{
    ///
    @trusted @nogc pure nothrow:
    this(in float v) { super(v); }
    //
    @trusted @nogc pure nothrow
    override float toInch(in ref UnitLength ul) const
    { return value * ul.em / ul.ppi; }
    //
    @trusted @nogc pure nothrow
    override int toPixel(in ref UnitLength ul) const
    { return cast(int)(value * ul.em); }
}

///
class EXValue : LengthValue
{
    ///
    @trusted @nogc pure nothrow:
    this(in float v) { super(v); }
    //
    @trusted @nogc pure nothrow
    override float toInch(in ref UnitLength ul) const
    { return value * ul.ex / ul.ppi; }
    //
    @trusted @nogc pure nothrow
    override int toPixel(in ref UnitLength ul) const
    { return cast(int)(value * ul.ex); }
}

///
class PercentageValue : LengthValue
{
    ///
    @trusted @nogc pure nothrow:
    this(in float v) { super(v); }
    //
    @trusted @nogc pure nothrow
    override float toInch(in ref UnitLength ul) const
    { return value * ul.size / ul.ppi; }
    //
    @trusted @nogc pure nothrow
    override int toPixel(in ref UnitLength ul) const
    { return cast(int)(value * ul.size); }
}

//------------------------------------------------------------------------------
/// 長さの取り扱い
/// $(LINK http://www.w3.org/TR/css3-values/)
struct UnitLength
{
    float size = 100; /// base value for percentage value, in pixels.
    float em = 15;    /// font size in pixel
    float ex = 15;    /// font height in pixel
    float ppi = 90;   /// userSpaceOnUse per inch.
                      /// userSpaceOnUse may equal to pixel.
}

///
struct UnitHV
{
    UnitLength h; ///
    UnitLength v; ///
}


//------------------------------------------------------------------------------
//
// CSS
//
//------------------------------------------------------------------------------

/// $LINK2(http://www.w3.org/Style/CSS/, CSS)を格納する。
class CSS : XML
{
    @trusted @nogc pure nothrow
    this(Ns n) {super(n);}

    ///
    @trusted @nogc pure nothrow
    this(Ns n, AXML[] s = null)
    { super(n); children = s; }

    //
    @property @trusted
    override CSS dup() const
    { return new CSS(name, dupChildren); }
}


/// CSSの一つのルールとその中身を表現する。
class CSSAttr : AXML
{
    const(Attribute) attr; ///
    const(Rule) rule; ///

    @trusted @nogc pure nothrow
    this(in Attribute a, in Rule r){ attr = a; rule = r; }

    @property @trusted override
    CSSAttr dup() const { return cast(CSSAttr)this; }

    ///
    @property @trusted pure override
    string toString() const
    {
        import std.string : join;
        return [rule.toString, " { ", attr.toCSSString, " }"].join;
    }
}

/// CSSの適用ルール
abstract class Rule
{
    /// xml がルールに適合するとき戻り値が true
    abstract bool match(in ref XML xml, XML[] parents) const;
    /// 文字列表現
    @property @trusted pure nothrow
    abstract override string toString() const;
}

/// 要素名でマッチ
class NameRule : Rule
{
    ///
    private const string name;
    ///
    @trusted @nogc pure nothrow:
    this(in string n){ name = n; }
    //
    override bool match(in ref XML xml, XML[] parents) const
    {return xml.name == name; }

    //
    @property @nogc pure nothrow
    override string toString() const { return name; }
}

/// id属性の値でマッチ
class IdRule : Rule
{
    private const string id; ///

    ///
    @trusted @nogc pure nothrow
    this(in string i){ id = i; }

    @trusted
    override bool match(in ref XML xml, XML[] parents) const
    { return xml.attr["id"] == id; }

    //
    @property @trusted pure nothrow
    override string toString() const
    { return "#" ~ id; }
}

/** class 属性の値でマッチ。

このルールを使う為には、class 属性の値が ClassValue である必要がある。
(== xml.attr.getAs!ClassValue("class") が非nullである必要がある。)
*/
class ClassRule : Rule
{
    ///
    private const string name;
    ///
    @trusted @nogc pure nothrow
    this(in string c){ name = c; }

    @trusted
    override bool match(in ref XML xml, XML[] parents) const
    {
        foreach (one; xml.attr.get!ClassValue("class"))
            if (one == name) return true;
        return false;
    }

    @property @trusted pure nothrow
    override string toString() const
    { return "." ~ name; }
}

/// 直上の親がルールに適合するかどうか。
class ParentRule : Rule
{
    ///
    private const(Rule) rule;
    ///
    @trusted @nogc pure nothrow
    this(in Rule r){ rule = r; }
    @trusted
    override bool match(in ref XML xml, XML[] parents) const
    { return 0 < parents.length && rule.match(parents[$-1], parents[0..$-1]); }

    @property @trusted pure nothrow
    override string toString() const
    { return rule.toString ~ " > "; }
}

/// 遡った親がルールに適合するかどうか。
class AncestorRule : Rule
{
    private const(Rule) rule;
    @trusted @nogc pure nothrow
    this(in Rule r){ rule = r; }
    @trusted
    override bool match(in ref XML xml, XML[] parents) const
    {
        for (size_t i = 0; i < parents.length; ++i)
            if (rule.match(parents[$-i-1], parents[0..$-i-1])) return true;
        return false;
    }

    @property @trusted pure nothrow
    override string toString() const { return rule.toString ~ " "; }
}

/// 全てのルールが適合するか。
class AndRule : Rule
{
    ///
    private const(Rule)[] rules;
    ///
    @trusted @nogc pure nothrow
    this(const(Rule)[] r){ rules = r; }
    @trusted
    override bool match(in ref XML xml, XML[] parents) const
    {
        foreach (r; rules)
            if (!r.match(xml, parents)) return false;
        return true;
    }

    @property @trusted pure nothrow
    override string toString() const
    {
        import std.string : join;
        auto buf = new string[rules.length];
        foreach (i, one; rules) buf[i] = one.toString;
        return buf.join;
    }
}
///
class OrRule : Rule
{
    private const(Rule)[] rules;
    @trusted @nogc pure nothrow
    this(const(Rule)[] r){ rules = r; }
    @trusted
    override bool match(in ref XML xml, XML[] parents) const
    {
        foreach (r; rules)
            if (r.match(xml, parents)) return true;
        return false;
    }

    @property @trusted pure nothrow
    override string toString() const
    {
        import std.string : join;
        auto buf = new string[rules.length];
        foreach (i, one; rules) buf[i] = one.toString;
        return buf.join;
    }
}

//==============================================================================
//------------------------------------------------------------------------------
//
// XMLのパーサ関連
//
//------------------------------------------------------------------------------
//==============================================================================

/// パーサの挙動を決定する。
enum XML_PARSER_PROPERTY
{
    STANDARD            = 0x00, ///
    LOWER_CASE          = 0x01, /// 要素名と属性名を小文字で統一する。
    OMITTABLE_CLOSETAG  = 0x02, ///
}

/** もう少し細かいパーサの挙動を制御する。

style 属性のみの専用のパーサを設けている。
**/
class XMLParserInfo
{
    XML current;  /// 現在の要素が代入される。
    XML parent;   /// 親。 diveCopy() によって代入される。
    string[string] ns; /// namespace。diveCopy() によって代入される。

    ///
    @trusted @nogc pure nothrow
    this() const { }
    /// ditto
    @trusted pure nothrow
    this(string defns){ ns = ["": defns, "xmlns": ""]; }
    /// ditto
    @trusted @nogc pure nothrow
    this(string[string] v){ ns = v; }
    //
    @trusted @nogc pure nothrow
    private this(XML c, XML p, string[string] v)
    { current = c; parent = p; ns = v; }

    /** XML構造の入れ子を下る度に呼び出される。

    この関数を override し、current.name に応じて戻り値の型を変えることで
    パーサの挙動を途中から変更できる。
    HTMLの中に、inline SVGが登場するような場合、current.name == "svg"
    の場合は、SVGInfo を返すようにするとイイ感じになる。

    この関数が呼ばれるタイミングでは、current.attrの中身は未解決。

    ネームスペースのスコープの問題があるので、自身と同じ型で続けてパースを
    したい場合でもインスタンスを分けておくべき。
    **/
    @trusted pure
    XMLParserInfo dive(Ns n)
    { return new XMLParserInfo(new XML(n), current, ns.dup); }

    /** 継承した関数から呼び出す。

    parent の値を設定し、nsのdupを代入してくれる。

    Params:
    i = あたらしいパーサ
    c = 現在パース中のxml。
    **/
    @trusted pure
    protected XMLParserInfo diveCopyTo(XMLParserInfo i, XML c)
    { i.current = c; i.parent = current; i.ns = ns.dup; return i; }

    /** 属性パーサのカスタム用

    継承クラスでこの関数を override することでパーサの挙動を変更する。

    Params:
    buf  = ここに読み取るべき文字列が入っている。
           クォートに到達したら empty になる。
           buf.peek でアクセスするとクォート以降の文字列も
           読み取ってしまう。
           この関数が呼び出される前後に buf.flush が呼ばれる。
    name = 属性の名前
    **/
    @trusted
    AttributeValue attrValueParser(TICache!char buf, in Ns key)
    { return buf.munchStringValue; }

    /** タグ以外の文字列のパーサカスタム用

    継承クラスでこの関数を override することでパーサの挙動を変更する。

    Params:
    buf = 次のタグに達したら buf.empty になる。
          文字実体参照は解決されない。
          cache.peekでは次のタグ以降も読み取ってしまう。
          この関数が呼び出される前後に buf.flush が呼び出される。
          この関数終了後に、buf.empty になるまで buf.popFront が呼び出さ
          れる。
    */
    @trusted
    AXML contentsParser(TICache!char buf)
    {
        import std.string : strip;
        for (; !buf.empty; buf.push){}
        return new XMLText(buf.istack.strip.expandEntity);
    }

    /** style 属性のパースに。

    この関数は、style属性の内部の各要素を、http://www.w3.org/Style/CSS/
    の名前空間で属性値へと展開する。

    内部で #(LINK #sworks.xml.XMLParserInfo.styleValueParser) を呼び出す。

    Bugs:
    dmd2.068.2
    <ol>
      <li>A lambda expression miss its outer environment at CTFE.</li>
    </ol>
    */
    protected @trusted
    void parseStyle(TICache!char buf)
    {
        import std.ascii : isWhite;
        alias A = AttributeValue;
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        auto T = this;
//
        for (; !buf.empty;)
        {
            buf.flush;
            auto key = buf.munchStyleKey;
            auto val = buf.enterPart!(char, STRIP.LOOSE)
                (";", b=>T.styleValueParser(b, key), false);
            if (val !is null) current.attr[key] = val;
        }
    }

    /** style属性の値をパースする。

    $(LINK #sworks.xml.XMLParserInfo.parseStyle) から呼び出される。
    */
    protected @trusted
    AttributeValue styleValueParser(TICache!char buf, in Ns)
    { return buf.munchStringValue; }
}


/** UTF8 文字列 を $(LINK2 #sworks.xml.AXML, AXMLクラス)にする。

Returns:
最初の要素とその中身のみを返す。
*/
@trusted
AXML toXML(XML_PARSER_PROPERTY P = XML_PARSER_PROPERTY.STANDARD)
    (string buf, XMLParserInfo info = null)
{ return buf.toCache.toXML!P(info); }
/// ditto
@trusted
AXML toXML(XML_PARSER_PROPERTY P = XML_PARSER_PROPERTY.STANDARD)
    (TICache!char buf, XMLParserInfo info = null)
{
    if (info is null) info = new XMLParserInfo(["xmlns": ""]);
    return buf.parseXML!P(info);
}

/** UTF8 文字列 を $(LINK2 #sworks.xml.XML, XML構造体)にする。
Returns:
name が空の XML構造体の children にパース結果を入れて返す。
*/
XML toXMLs(XML_PARSER_PROPERTY P = XML_PARSER_PROPERTY.STANDARD)
    (string buf, XMLParserInfo info = null)
{ return buf.toCache.toXMLs!P(info);}
/// ditto
XML toXMLs(XML_PARSER_PROPERTY P = XML_PARSER_PROPERTY.STANDARD)
    (TICache!char buf, XMLParserInfo info = null)
{
    if (info is null) info = new XMLParserInfo(["xmlns": ""]);
    auto xml = new XML;
    for (; !buf.empty;)
        if (auto c = buf.parseXML!P(info)) xml.children ~= c;
    return xml;
}

//------------------------------------------------------------------------------
//
// TICache!char の suger
//
//------------------------------------------------------------------------------

/** 長さの切り出し。

$(LINK http://www.w3.org/TR/2008/REC-CSS2-20080411/syndata.html#length-units)
*/
@trusted
AttributeValue munchLength(TICache!char buf)
{
    auto f = buf.munchFloating;
    buf.stripLeftWhite;
    switch(buf.front)
    {
        case '%': return new PercentageValue(f * 0.01);
        case '"':
        case ';': return new LengthValue(f);
        default:
    }
    switch(buf.peek(2))
    {
        case "em": return new EMValue(f);
        case "ex": return new EXValue(f);
        case "px": return new LengthValue(f);
        case "in": return new InchValue(f);
        case "cm": return new InchValue(f / 2.54);
        case "mm": return new InchValue(f / 25.4);
        case "pt": return new InchValue(f / 72);
        case "pc": return new InchValue(f / 6);
        default:
    }
    return new LengthValue(f);
}

/// 色のパース
@trusted
ColorValue munchColor(TICache!char buf)
{
    buf.stripLeftWhite;
    if      ('#' == buf.front)
    {
        buf.popFront;
        uint i = 0;
        uint counter = 0;
        uint color;
        for (auto c = buf.front; !buf.empty; c = buf.popFront, ++counter)
        {
            i <<= 4;
            if      ('0' <= c && c <= '9') i += (c - '0');
            else if ('a' <= c && c <= 'f') i += (c - 'a' + 10);
            else if ('A' <= c && c <= 'F') i += (c - 'A' + 10);
        }
        if (3 == counter)
            i = ((i & 0x00000f00) << 12) | ((i & 0x00000f00) << 8)
              | ((i & 0x000000f0) << 8)  | ((i & 0x000000f0) << 4)
              | ((i & 0x0000000f) << 4)  | ((i & 0x0000000f));
        color = (i & 0xff00ff00) | ((i & 0xff0000)>>16) | ((i & 0xff)<<16);
        return new ColorValue(color);
    }
    else if ("url(#" == buf.peek(5)) return null;
    else if (buf.peekPop("none")) return null;
    else
    {
        auto w = buf.toWORD;
        if (auto pc = w in COLOR) return new ColorValue(*pc);
        else throw new Exception("an unexpected word as color : " ~ w);
    }
    return null;
}

///
@trusted
ClassValue munchClassValue(TICache!char buf)
{
    string[] val;
    for (; !buf.empty;)
    {
        buf.stripLeftWhite;
        auto c = buf.toWORD;
        if (0 < c.length) val ~= c;
    }

    return new ClassValue(val);
}

///
@trusted
StringValue munchStringValue(TICache!char buf)
{
    import std.string : strip;
    for (; !buf.empty; buf.push){}
    return new StringValue(buf.istack.strip);
}

/// 文字実体参照を解決する。 &amp;amp; &amp;gt; &amp;lt; に対応している。
@trusted pure
string expandEntity(const(char)[] buf)
{
    import std.algorithm : find;
    import std.array : Appender;

    Appender!string result;
    result.reserve(buf.length);
    for (;;)
    {
        auto r = buf.find("&");
        if (0 == r.length) { result.put(buf); break; }
        result.put(buf[0..$-r.length]);
        buf = r[1..$];
        r = buf.find(";");
        if (0 == r.length) { result.put("&"); result.put(buf); break; }
        switch(buf[0..$-r.length])
        {
            case        "amp": result.put("&");
            break; case "lt": result.put("<");
            break; case "gt": result.put(">");
            break; default:
                throw new Exception("undefined entity: \""
                                   ~ buf[0..$-r.length].idup ~ "\"");
        }
        buf = r[1..$];
    }
    return result.data;
}

//------------------------------------------------------------------------------
//
// XMLパーサ用ツール
//
//------------------------------------------------------------------------------

/* buf から XML をパースする。ここの挙動はカスタムしない。

Params:
buf  = $(LINK #sworks.base.cached_buffer.TICache).
       ここから XML を取り出す。
info = 現在のパース情報(現在の要素とか)を格納している。

Returns:
最後に出会ったタグを返す。
この関数の戻り値としてのみ $(LINK #sworks.xml.XMLClose) というクラスが
存在する。
**/
@trusted private
AXML parseXML(XML_PARSER_PROPERTY P = XML_PARSER_PROPERTY.STANDARD)
    (TICache!char buf, XMLParserInfo info)
{
    enum LC = P & XML_PARSER_PROPERTY.LOWER_CASE;
    enum OC = P & XML_PARSER_PROPERTY.OMITTABLE_CLOSETAG;

    import std.string : strip;
    static if (LC) import std.uni : toLower;

    buf.stripLeftXMLWhite;
    if      (buf.empty) return null; // 何もなかった
    else if (buf.peekPop("<![CDATA[")) // js とか css で使うやつ。
        return buf.enterPart!(char, STRIP.STRICT)("]]>",
             b=>info.contentsParser(b));
    else if ('<' == buf.front)     // タグに出会った
    {
        // ここで info の参照先が変わる(diveが呼ばれる)可能性あり。
        auto tag = buf.munchTag!LC(info); // タグの取り出し
        if (auto otag = info.current) // 開始タグだった
        {
            // 中身のパース
            for (; !buf.empty;)
            {
                // 中身を1個パース
                auto child = buf.parseXML!P(info);
                if (auto ctag = cast(XMLClose)child) // 終了タグがきた。
                {
                    if (otag.name != ctag.name) // 終了タグと開始タグが違う。
                    {
                        static if (!OC) throw new Exception(
                            otag.getOpenTagString ~ "!=" ~ ctag.toString);
                        if (auto p = info.parent) // 親がある場合は親に追加
                        {
                            p.children ~= otag;
                            p.children ~= otag.children;
                            otag.children = null;
                        }
                        return ctag; // 終了タグを親に通知
                    }
                    break;
                }
                else if (child !is null) // 終了タグじゃないのがきた。
                    otag.children ~= child;
            }
        }
        return tag;
    }
    else // 文字列に出会った
        return buf.enterPart!(char, STRIP.NONE)("<", b=>info.contentsParser(b));

    return null;
}

// パース途中で使うだけのん。
private class XMLClose : AXML
{
    //
    Ns name;
    //
    @trusted @nogc pure nothrow
    this(Ns n){ name = n; }

    override @property @trusted pure
    string toString() const
    { import std.string : join; return ["</", name, ">"].join; }

    override @property @trusted @disable
    AXML dup() const { return null; }
}

// バッファ先頭からタグを切り出す。
// OPEN TAG だった場合は、info.current に XML を代入する。
// それ以外では info.current には null が代入される。
@trusted private
AXML munchTag(bool LC)(TICache!char buf, ref XMLParserInfo info)
{
    assert(info !is null);
    assert('<' == buf.front);
    if ('/' == buf.popFront) // CLOSE TAG
    {
        buf.popFront;
        auto name = buf.munchNs!LC(info.ns, info.ns.get("", ""));
        buf.findSkip('>');
        info.current = null;
        return new XMLClose(name);
    }

    //                          OPEN TAG
    info = info.dive(buf.munchNs!LC(info.ns, info.ns.get("", "")));
    buf.parseAttributes!LC(info);

    //                          EMPTY TAG
    if      (buf.peekPop("/>"))
    { auto x = info.current; info.current = null; return x; }
    //                          AN ELEMENT MAY HAVE CONTENTS
    else if (buf.peekPop(">")) return info.current;
    else throw new Exception("unterminated element tag <" ~ info.current.name
                            ~ ">. the front is '" ~ buf.front ~ "'");
    assert(0);
}

// 属性切り出し
// Params:
//   LC = all keys are lower case, if true.
@trusted private
void parseAttributes(bool LC)(TICache!char buf, XMLParserInfo info)
{
    assert(info !is null);
    alias A = AttributeValue;
    static if (LC) import std.uni : toLower;
    A val;
    for (;;)
    {
        buf.stripLeftWhite;
        if     (buf.empty) break;
        else if ('>' == buf.front || '/' == buf.front) break;

        auto key = buf.munchNs!LC(info.ns, info.current.name.uri);
        if (key.empty) break;

        buf.stripLeftWhite;
        if ('=' == buf.front)
        {
            buf.popFront;
            buf.stripLeftWhite;
            val = buf.enterString!char("\"", b=>info.attrValueParser(b, key));
        }
        else val = new StringValue(key);

        if (val !is null)
        {
            info.current.attr[key] = val;

            // xmlns属性の処理
            if      (key == "xmlns")
            {
                auto n = val.toString;
                info.ns[""] = n;
                if (info.current.name.ns.length == 0)
                    info.current.name.uri = n;
            }
            else if (key.ns == "xmlns")
            {
                auto n = val.toString;
                info.ns[key] = n;
                if (info.current.name.ns == key.value)
                    info.current.name.uri = n;
            }
        }
    }
}

// style 属性の中身の名前部分を切り出す。
@trusted private
Ns munchStyleKey(TICache!char buf)
{
    buf.stripLeftCSSWhite;
    auto key = buf.munchUntil!"a==':' || a == ' ' || a == '\t'";
    buf.findSkip(':');
    buf.stripLeftCSSWhite;
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// BUG
    if (__ctfe) return Ns(key);
    else return Ns(key, CSS_URI);
}


// 文字列先頭から XML における、空白、コメントなどを取り除く。
@trusted
private void stripLeftXMLWhite(TICache!char buf)
{
    import std.exception : enforce;
    for (;;)
    {
        buf.stripLeftWhite;
        if      (buf.empty) break;
        else if ('<' != buf.front) break;
        else if (buf.peekPop("<!--"))
            buf.findSkip("-->").enforce("unterminated comment block.");
        else if ("<![" == buf.peek(3)) break;
        else if (buf.peekPop("<!", "<?"))
            buf.findSkip('>').enforce("unterminated declaration element.");
        else break;
    }
}

// 先頭1トークン切り出し
private alias munchToken = munchUntil!(q{!(('a' <= a && a <= 'z')
                                        || ('A' <= a && a <= 'Z')
                                        || ('0' <= a && a <= '9')
                                        || '_' == a || '-' == a)}, char);

// 名前空間付き名の切り出し。
// LC = makes all names lower case, if true.
@trusted private
Ns munchNs(bool LC)(TICache!char buf, string[string] ns, lazy string def = "")
{
    import std.string : toLower;
    import std.exception : enforce;

    buf.stripLeftWhite;
    static if (LC)
        //!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        // why idup needed? under linux, dmd2.069.2
        auto t1 = buf.munchToken.idup.toLower;
    else
        auto t1 = buf.munchToken;
    if (buf.front == ':') // ネームスペース切り出し。
    {
        buf.popFront;
        auto t2 = buf.munchToken;
        static if (LC) t2 = t2.toLower;
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// BUG
        if (__ctfe) return Ns(t2);
        else
        {
            auto puri = enforce(t1 in ns, t1 ~ " is not in namespace.");
            return Ns(t2, *puri, t1);
        }
    }
    else // ネームスペースなかった。
    {
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// BUG
        if (__ctfe) return Ns(t1);
        else return Ns(t1, def);
    }
}

//------------------------------------------------------------------------------
// 色名データベース
@trusted @nogc pure nothrow private
uint rgb(uint r, uint g, uint b) { return r | g << 8 | b << 16; }

// $(LINK, http://www.w3.org/TR/SVG/types.html#ColorKeywords#ColorKeywords)
enum COLOR =
["aliceblue": rgb(240, 248, 255),
 "antiquewhite": rgb(250, 235, 215),
 "aqua": rgb(0, 255, 255),
 "aquamarine": rgb(127, 255, 212),
 "azure": rgb(240, 255, 255),
 "beige": rgb(245, 245, 220),
 "bisque": rgb(255, 228, 196),
 "black": rgb(0, 0, 0),
 "blanchedalmond": rgb(255, 235, 205),
 "blue": rgb(0, 0, 255),
 "blueviolet": rgb(138, 43, 226),
 "brown": rgb(165, 42, 42),
 "burlywood": rgb(222, 184, 135),
 "cadetblue": rgb(95, 158, 160),
 "chartreuse": rgb(127, 255, 0),
 "chocolate": rgb(210, 105, 30),
 "coral": rgb(255, 127, 80),
 "cornflowerblue": rgb(100, 149, 237),
 "cornsilk": rgb(255, 248, 220),
 "crimson": rgb(220, 20, 60),
 "cyan": rgb(0, 255, 255),
 "darkblue": rgb(0, 0, 139),
 "darkcyan": rgb(0, 139, 139),
 "darkgoldenrod": rgb(184, 134, 11),
 "darkgray": rgb(169, 169, 169),
 "darkgreen": rgb(0, 100, 0),
 "darkgrey": rgb(169, 169, 169),
 "darkkhaki": rgb(189, 183, 107),
 "darkmagenta": rgb(139, 0, 139),
 "darkolivegreen": rgb(85, 107, 47),
 "darkorange": rgb(255, 140, 0),
 "darkorchid": rgb(153, 50, 204),
 "darkred": rgb(139, 0, 0),
 "darksalmon": rgb(233, 150, 122),
 "darkseagreen": rgb(143, 188, 143),
 "darkslateblue": rgb(72, 61, 139),
 "darkslategray": rgb(47, 79, 79),
 "darkslategrey": rgb(47, 79, 79),
 "darkturquoise": rgb(0, 206, 209),
 "darkviolet": rgb(148, 0, 211),
 "deeppink": rgb(255, 20, 147),
 "deepskyblue": rgb(0, 191, 255),
 "dimgray": rgb(105, 105, 105),
 "dimgrey": rgb(105, 105, 105),
 "dodgerblue": rgb(30, 144, 255),
 "firebrick": rgb(178, 34, 34),
 "floralwhite": rgb(255, 250, 240),
 "forestgreen": rgb(34, 139, 34),
 "fuchsia": rgb(255, 0, 255),
 "gainsboro": rgb(220, 220, 220),
 "ghostwhite": rgb(248, 248, 255),
 "gold": rgb(255, 215, 0),
 "goldenrod": rgb(218, 165, 32),
 "gray": rgb(128, 128, 128),
 "grey": rgb(128, 128, 128),
 "green": rgb(0, 128, 0),
 "greenyellow": rgb(173, 255, 47),
 "honeydew": rgb(240, 255, 240),
 "hotpink": rgb(255, 105, 180),
 "indianred": rgb(205, 92, 92),
 "indigo": rgb(75, 0, 130),
 "ivory": rgb(255, 255, 240),
 "khaki": rgb(240, 230, 140),
 "lavender": rgb(230, 230, 250),
 "lavenderblush": rgb(255, 240, 245),
 "lawngreen": rgb(124, 252, 0),
 "lemonchiffon": rgb(255, 250, 205),
 "lightblue": rgb(173, 216, 230),
 "lightcoral": rgb(240, 128, 128),
 "lightcyan": rgb(224, 255, 255),
 "lightgoldenrodyellow": rgb(250, 250, 210),
 "lightgray": rgb(211, 211, 211),
 "lightgreen": rgb(144, 238, 144),
 "lightgrey": rgb(211, 211, 211),
 "lightpink": rgb(255, 182, 193),
 "lightsalmon": rgb(255, 160, 122),
 "lightseagreen": rgb(32, 178, 170),
 "lightskyblue": rgb(135, 206, 250),
 "lightslategray": rgb(119, 136, 153),
 "lightslategrey": rgb(119, 136, 153),
 "lightsteelblue": rgb(176, 196, 222),
 "lightyellow": rgb(255, 255, 224),
 "lime": rgb(0, 255, 0),
 "limegreen": rgb(50, 205, 50),
 "linen": rgb(250, 240, 230),
 "magenta": rgb(255, 0, 255),
 "maroon": rgb(128, 0, 0),
 "mediumaquamarine": rgb(102, 205, 170),
 "mediumblue": rgb(0, 0, 205),
 "mediumorchid": rgb(186, 85, 211),
 "mediumpurple": rgb(147, 112, 219),
 "mediumseagreen": rgb(60, 179, 113),
 "mediumslateblue": rgb(123, 104, 238),
 "mediumspringgreen": rgb(0, 250, 154),
 "mediumturquoise": rgb(72, 209, 204),
 "mediumvioletred": rgb(199, 21, 133),
 "midnightblue": rgb(25, 25, 112),
 "mintcream": rgb(245, 255, 250),
 "mistyrose": rgb(255, 228, 225),
 "moccasin": rgb(255, 228, 181),
 "navajowhite": rgb(255, 222, 173),
 "navy": rgb(0, 0, 128),
 "oldlace": rgb(253, 245, 230),
 "olive": rgb(128, 128, 0),
 "olivedrab": rgb(107, 142, 35),
 "orange": rgb(255, 165, 0),
 "orangered": rgb(255, 69, 0),
 "orchid": rgb(218, 112, 214),
 "palegoldenrod": rgb(238, 232, 170),
 "palegreen": rgb(152, 251, 152),
 "paleturquoise": rgb(175, 238, 238),
 "palevioletred": rgb(219, 112, 147),
 "papayawhip": rgb(255, 239, 213),
 "peachpuff": rgb(255, 218, 185),
 "peru": rgb(205, 133, 63),
 "pink": rgb(255, 192, 203),
 "plum": rgb(221, 160, 221),
 "powderblue": rgb(176, 224, 230),
 "purple": rgb(128, 0, 128),
 "red": rgb(255, 0, 0),
 "rosybrown": rgb(188, 143, 143),
 "royalblue": rgb(65, 105, 225),
 "saddlebrown": rgb(139, 69, 19),
 "salmon": rgb(250, 128, 114),
 "sandybrown": rgb(244, 164, 96),
 "seagreen": rgb(46, 139, 87),
 "seashell": rgb(255, 245, 238),
 "sienna": rgb(160, 82, 45),
 "silver": rgb(192, 192, 192),
 "skyblue": rgb(135, 206, 235),
 "slateblue": rgb(106, 90, 205),
 "slategray": rgb(112, 128, 144),
 "slategrey": rgb(112, 128, 144),
 "snow": rgb(255, 250, 250),
 "springgreen": rgb(0, 255, 127),
 "steelblue": rgb(70, 130, 180),
 "tan": rgb(210, 180, 140),
 "teal": rgb(0, 128, 128),
 "thistle": rgb(216, 191, 216),
 "tomato": rgb(255, 99, 71),
 "turquoise": rgb(64, 224, 208),
 "violet": rgb(238, 130, 238),
 "wheat": rgb(245, 222, 179),
 "white": rgb(255, 255, 255),
 "whitesmoke": rgb(245, 245, 245),
 "yellow": rgb(255, 255, 0),
 "yellowgreen": rgb(154, 205, 50)
];

//==============================================================================
//------------------------------------------------------------------------------
//
// CSS パーサ
//
//------------------------------------------------------------------------------
//==============================================================================

///
enum CSS_URI = "http://www.w3.org/Style/CSS/";

@trusted
AXML[] toCSS(TICache!char buf, XMLParserInfo info)
{
    import std.array : Appender;
    Appender!(AXML[]) attr;
    for (; !buf.empty;)
        if (auto rule = buf.munchRule)
            attr.put(new CSSAttr(buf.toCSSAttr(info), rule));
    return attr.data;
}

//
@trusted private
Attribute toCSSAttr(TICache!char buf, XMLParserInfo info)
{
    import std.string : strip;
    buf.stripLeftCSSWhite;
    assert(buf.empty || '{' == buf.front, buf.peekBetter);
    buf.popFront;

    return buf.enterPart!(char, STRIP.STRICT)("}", (b)
    {
        Attribute attr;
        for (; !b.empty;)
        {
            b.enterPart!(char, STRIP.LOOSE)(";", (b2)
            {
                auto key = b2.munchStyleKey;
                auto val = info.styleValueParser(b2, key);
                if (val !is null) attr[key] = val;
            }, false);
        }
        return attr;
    });
}


//
@trusted
private void stripLeftCSSWhite(TICache!char buf)
{
    import std.exception : enforce;
    for (;;)
    {
        buf.stripLeftWhite;
        if      (buf.empty) break;
        else if (buf.peekPop("/*"))
            buf.findSkip("*/").enforce("unterminated comment block.");
        else break;
    }
}

//
@trusted
private Rule munchRule(TICache!char buf)
{
    import std.ascii : isWhite;
    Rule r;

    for (; !buf.empty;)
    {
        buf.stripLeftCSSWhite;
        bool parentFlag = false;
        if      ('>' == buf.front)
        {
            parentFlag = true;
            buf.popFront;
            buf.stripLeftCSSWhite;
        }
        else if ('{' == buf.front) break;

        Rule[] r2;
        for (; !buf.empty;)
        {
            if      (buf.front.isWhite) break;
            else if ('{' == buf.front) break;
            else if ('#' == buf.front)
            {
                buf.popFront;
                r2 ~= new IdRule(buf.toWORD);
            }
            else if ('.' == buf.front)
            {
                buf.popFront;
                r2 ~= new ClassRule(buf.toWORD);
            }
            else
            {
                r2 ~= new NameRule(buf.toWORD);
            }
        }

        if      (r is null)
        {
            if      (1 < r2.length) r = new AndRule(r2);
            else if (0 < r2.length) r = r2[0];
        }
        else if (parentFlag) r = new AndRule(new ParentRule(r) ~ r2);
        else r = new AndRule(new AncestorRule(r) ~ r2);
    }

    return r;
}


//##############################################################################
// compile to do unittest:
// dmd -Isrc -debug -debug=BUGCHECK_4 -unittest -main src\sworks\xml.d .\src\sworks\base\aio.d .\src\sworks\base\cached_buffer.d .\src\sworks\base\ctfe.d;./xml.exe

/* This was fixed, at least at dmd2.071.0
// Assertion failure: '0' on line 3135 in file 'interpret.c'
debug(BUGCHECK_1) unittest
{
    class A { int a; this(int v) { a = v; } }
    enum a = ()
    {
        scope auto a = new A(2);
        return 3;
    }();
    a.writeln;
}
*/

// Error: non-constant expression [1:2].
debug(BUGCHECK_2) unittest
{
    class A { int[int] a; this(int[int] i){ a = i; }}
    enum { a = new A([1:2]), }
    a.writeln;
}

// Error 42: Symbol Undefined.
debug(BUGCHECK_3) unittest
{
    enum e = {
        struct A{int[] x;}
        A[] a;
        return a ~ A();
    }();
    e.writeln;
}

//toHash doesn't execute at CTFE.
debug(BUGCHECK_4) unittest
{
    struct S
    {
        int v;
        bool opEquals(in ref S r) const { return true; }
        size_t toHash() const { return 0; }
    }

    string func()
    {
        int[S] s;
        s[S(5)] = 10;
        if (S(6) in s) return "OK";
        else return "NG";
    }

    enum A = func;
    auto B = func;
    writeln("BUGCHECK_4");
    writeln("compile time: ", A);
    writeln("run time: ", B);
}

//##############################################################################

debug(xml):

struct Dummy { AXML xml; }
void main()
{
    enum sample =

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

    enum XPP1 = XML_PARSER_PROPERTY.LOWER_CASE;
    enum XPP2 = XML_PARSER_PROPERTY.OMITTABLE_CLOSETAG;
    enum XPP3 = XML_PARSER_PROPERTY.OMITTABLE_CLOSETAG
              | XML_PARSER_PROPERTY.LOWER_CASE;

 enum xml = sample.toXML.toString;
    xml.writeln;
    // foreach (one; xml)
    //     foreach (name, val; one.attr) writeln(name.value, "=", val.bareValue);
}



