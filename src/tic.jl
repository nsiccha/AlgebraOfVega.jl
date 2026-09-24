# === @tic timer (for profiling hot paths) =====================================
# `@tic "label"` inside a function body prints elapsed ms since the previous
# `@tic` call. `@tic expr` wraps an expression and prints its timing.
_TIC_VERSION = 7
mutable struct Tic
    label::String
    _ns::UInt64
end
macro tic(arg)
    v = esc(:_tic_)
    file = String(__source__.file)
    line = __source__.line
    _tic_expand(arg, v, file, line)
end

# Two macro forms: `@tic "label"` (or `@tic "interp $x"`) records a checkpoint
# under that label; `@tic expr` times an expression and uses `string(arg)` as
# the label. Dispatching on `arg`'s type splits the two forms; the inner head
# test on Expr stays a value comparison (`Meta.isexpr(arg, :string)` is the
# string-interpolation literal form), which is the AoT-recommended exception
# to the "no Bool predicates" rule.
_tic_expand(arg::String, v, file, line) = _tic_emit_label(esc(arg), v, file, line)
_tic_expand(arg::Expr, v, file, line) = arg.head === :string ?
    _tic_emit_label(esc(arg), v, file, line) :
    _tic_emit_expr(arg, v, file, line)
_tic_expand(arg, v, file, line) = _tic_emit_expr(arg, v, file, line)

_tic_emit_label(label, v, file, line) = quote
    if $(Expr(:isdefined, v))
        _el = (time_ns() - $v._ns) / 1e6
        @warn "[v$(_TIC_VERSION)] $($v.label) — $($label): $(round(_el; digits=1))ms" _file=$file _line=$line
        $v._ns = time_ns()
    else
        $v = Tic($label, time_ns())
    end
end

_tic_emit_expr(arg, v, file, line) = begin
    label_str = string(arg)
    expr = esc(arg)
    val = gensym(:tic_val)
    t0 = gensym(:tic_t0)
    el = gensym(:tic_el)
    quote
        $t0 = time_ns()
        $val = $expr
        $el = (time_ns() - $t0) / 1e6
        if $(Expr(:isdefined, v))
            @warn "[v$(_TIC_VERSION)] $($v.label) — $($label_str): $(round($el; digits=1))ms" _file=$file _line=$line
        else
            @warn "[v$(_TIC_VERSION)] $($label_str): $(round($el; digits=1))ms" _file=$file _line=$line
        end
        $val
    end
end
# === end @tic =================================================================
