/**
 * Date:       2016-Jan-28 00:38:35
 * Authors:
 * License:
 **/
module sworks.base.traits;

///
template isPublicMethod(T, string N)
{
    import std.traits : isSomeFunction, functionAttributes, FunctionAttribute;
    static
    template _impl(alias F)
    {
        static if (__traits(getProtection, F) == "public" &&
                   isSomeFunction!F &&
                   (functionAttributes!F & FunctionAttribute.property) == 0)
            enum _impl = true;
        else
            enum _impl = false;
    }

    alias isPublicMethod = _impl!(__traits(getMember, T, N));
}

///
template isMemberVariable(T, string N)
{
    enum isMemberVariable =
        __traits(getProtection, __traits(getMember, T, N)) == "public" &&
        is(typeof(__traits(getMember, T, N).offsetof));
}

///
template isPropertyMethod(T, string N)
{
    import std.traits : isCallable, functionAttributes, FunctionAttribute;

    static if (__traits(getProtection, __traits(getMember, T, N)) == "public" &&
               isCallable!(__traits(getMember, T, N)) &&
               (functionAttributes!(__traits(getMember, T, N)) &
                FunctionAttribute.property))
        enum isPropertyMethod = true;
    else
        enum isPropertyMethod = false;
}

///
template isGetter(T, string N)
{
    import std.traits : Parameters;
    static if (isPropertyMethod!(T, N))
    {
        enum isGetter =
        {
            foreach (i, one; __traits(getOverloads, T, N))
                if (0 == Parameters!one.length) return true;
            return false;
        }();
    }
    else
        enum isGetter = false;
}

///
template isSetter(T, string N)
{
    import std.traits : Parameters, functionAttributes, FunctionAttribute;
    static if (isPropertyMethod!(T, N))
    {
        enum isSetter =
        {
            foreach (one; __traits(getOverloads, T, N))
            {
                alias Ps = Parameters!one;
                if (1 == Ps.length || 0 == Ps.length &&
                    functionAttributes!one & FunctionAttribute.ref_)
                    return true;
            }
            return false;
        }();
    }
    else
        enum isSetter = false;
}

///
template SetterType(T, string N)
{
    import std.traits : Parameters, functionAttributes, FunctionAttribute;

    enum setterPos =
    {
        foreach (i, one; __traits(getOverloads, T, N))
        {
            alias Ps = Parameters!one;
            if (1 == Ps.length || 0 == Ps.length &&
                functionAttributes!one & FunctionAttribute.ref_)
                return i;
        }
        return -1;
    }();

    static if (isMemberVariable!(T, N))
        alias SetterType = typeof(__traits(getMember, T, N));
    else static if (
        1 == Parameters!(__traits(getOverloads, T, N)[setterPos]).length)
        alias SetterType =
            Parameters!(__traits(getOverloads, T, N)[setterPos])[0];
    else
        alias SetterType = ReturnType!(__traits(getOverloads, T, N)[setterPos]);
}

