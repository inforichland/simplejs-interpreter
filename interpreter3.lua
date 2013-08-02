
--- interpreter for parse tree produced in parser3.lua

require( 'environment3' )
local string = require( 'string' )

function dump( t, indent )
   indent = indent or 0

   local function switch( k, v )
      if k ~= 'scope' then --and k ~= 'env' then
	 if type( v ) == 'table' then
	    if v ~= t then
	       io.write( string.rep( ' ', indent ), string.format('  %s :\n', k ) )
	       dump( v, indent + 2 )
	    end
	 elseif type( v ) == 'string' then
	    io.write( string.rep( ' ', indent ), string.format( '  %s : %s\n', k, v ) )
	 elseif type( v ) == 'number' then
	    io.write( string.rep( ' ', indent ), string.format( '  %s : %f\n', k, v ) )
	 end
      end
   end

   for k, v in pairs( t ) do
      switch( k, v )
   end
end


-- arity: unary, binary, ternary, name, function, literal, this, statement

-- runtime-specific variables - not modifiable during runtime (?)
local runtime_variables = {}

-- current environment
local m_env = nil

-- change literal "\n" into newline, etc.
local fixed_escapes = {
   [ '\\n' ] = '\n',
   [ '\\r' ] = '\r',
   [ '\\t' ] = '\t',
}
local function fix_escapes( str )
   local s,_ = string.gsub( str, "\\[nrt]", fixed_escapes )
   return s
end

-- runtime-specific functions - not modifiable during runtime
local runtime_functions = {}
do runtime_functions = {
      [ 'print' ] =
	 function( things )
	    for _, v in ipairs( things ) do
	       if type( v ) == 'string' then
		  io.write( fix_escapes( v ) )
	       elseif type( v ) == 'number' then
		  io.write( tostring( v ) )
	       else
		  error( string.format( 'Invalid argument to "print": %s', v ) )
	       end
	    end
	 end,

      [ 'println' ] =
	 function( things )
	    runtime_functions[ 'print' ]( things )
	    print()
	 end,
}
end

-- forward declaration
local interpret = nil

-- evaluate a function's arguments before it's evaluated
local function evaluate_args( args )
   local results = {}
   for _, v in ipairs( args ) do
      if v.arity == 'name' then
	 local val = m_env:find( v.value )
	 table.insert( results, val )
      elseif v.arity == 'literal' then
	 table.insert( results, v.value )
      elseif v.arity == 'unary' or v.arity == 'binary' or v.arity == 'ternary' then
	 local result = interpret( v )
	 table.insert( results, result )
      elseif v.arity == 'function' then
	 error( 'eval_args, function' )
      elseif type( v ) == 'string' then
         table.insert( results, v )
      elseif type( v ) == 'number' then
         table.insert( results, v )
      end
   end
   return results
end

-- evaluate arguments for operators
function eval_op_args( tree )
   if tree.arity == 'binary' then
      local arg1 = evaluate_args{ tree.first }
      local arg2 = evaluate_args{ tree.second }
      return { arg1, arg2 }
   elseif tree.arity == 'unary' then
      local arg = evaluate_args{ tree.first }
      return { arg1 }
   elseif tree.arity == 'ternary' then
      local arg1 = evaluate_args{ tree.first }
      local arg2 = evaluate_args{ tree.second }
      local arg3 = evaluate_args{ tree.third }
      return { arg1, arg2, arg3 }
   end
end

local function shallow_copy_table( t )
   local n = {}
   for k, v in pairs( t ) do
      n[ k ] = v
   end
   return n
end

-- interpret a user-defined function
local function interpret_func( func, args )
   -- create new environment for bindings
   m_env = m_env:create()
   -- fill in bindings

   if #func.args ~= #args then
      error( 'Wrong number of arguments to function' )
   end

   -- bind arguments
   local evaled_args = evaluate_args( args )
   for i,v in ipairs( evaled_args ) do
      m_env:bind( func.args[ i ].value, v )
   end

   -- execute
   local result = interpret( func.body )

   -- now release the function's bindings
   m_env = m_env:pop()

   return result
end

-- create a handler for binary operators
local function interp_handler_binary( f )
   return function( tree )
      local evaled_args = eval_op_args( tree )
      if #evaled_args ~= 2 then
         error( 'Wrong number of args' )
      else
         local arg1, arg2 = evaled_args[ 1 ][ 1 ], evaled_args[ 2 ][ 1 ]
         return f( arg1, arg2 )
      end
   end
end

local interp_handlers = {
   [ 'return' ] =
      function( tree )
         local result = evaluate_args{ tree.first }
         return result[ 1 ]
      end,

   [ 'function' ] = -- function definition
      function ( tree )
	 local a, b = tree.first, tree.second

	 -- check to see if this is a closure
	 -- (if it uses variables which are not arguments)
	 -- capture them in a new environment

	 local foo = {
	    [ 'args' ] = a,
	    [ 'body' ] = b,
	    --['env'] = shallow_copy_table( m_env ),
	    value = '(',
	 }
	 return foo
      end,

   [ '(' ] = -- function call
      function( tree )
         local func_name = tree.first.value
         local func = m_env:find( func_name )

	 -- builtin function or user-created?
         if type( func ) == 'function' then
	    local args = tree.second
	    local result = nil
	    -- create a new environment for this function call
	    m_env = m_env:create()
	    -- call the function
	    local evaled_args = evaluate_args( args )
            result = func( evaled_args )
	    -- now release the function's bindings
	    m_env = m_env:pop()
	 elseif type( func ) == 'table' then
	    -- user-created
	    result = interpret_func( func, tree.second )
         else
            error( string.format( 'Unknown function %s', func_name ) )
         end
         return result
      end,

   [ '=' ] = -- assignment
      function( tree )
         if tree.second.arity == 'literal' then
            m_env:bind( tree.first.value, tree.second.value )
         else
            local result = interpret( tree.second )
            m_env:bind( tree.first.value, result )
         end
      end,

   [ '+' ] = interp_handler_binary( function( a, b ) return a + b end ),
   [ '-' ] = interp_handler_binary( function( a, b ) return a - b end ),
   [ '*' ] = interp_handler_binary( function( a, b ) return a * b end ),
   [ '/' ] = interp_handler_binary( function( a, b ) return a / b end ),
}

-- interpret a parse tree
interpret = function( tree )
   local ret = nil

   -- multiple statements or a single statement?
   if table.maxn( tree ) == 0 then
      local value = tree.value

      local handler = interp_handlers[ value ]
      if handler then
         ret = handler( tree )
      else
         error( string.format( 'Invalid parse tree for %s', value )  )
      end
   else
      for _, stmt in ipairs( tree ) do
         ret = interpret( stmt )
      end
   end

   return ret
end

local function init()
   m_env = env.create()

   for name, value in pairs( runtime_functions ) do
      m_env:bind( name, value )
   end

   for name, value in pairs( runtime_variables ) do
      m_env:bind( name, value )
   end

end

-- return public interface
-- create the naked 'module'
local interpreter = {
   init = init,
   interpret = interpret,
}
interpreter.__index = interpreter

return interpreter
