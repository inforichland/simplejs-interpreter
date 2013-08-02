local lexer = require( 'lexer3' )
local parser = require( 'parser3' )
local interpreter = require( 'interpreter3' )

function report_error( str )
  error( str )
end

function dump_table( t, indent )
  indent = indent or 0

   for k, v in pairs( t ) do
      if k == 'first' or k == 'second' or k == 'value' or k == 'arity' or type( k ) == 'number' then
         if type( v ) == 'table' then
            if v ~= t then
               io.write( string.rep( ' ', indent ), string.format('  %s :\n', k ) )
               dump_table( v, indent + 2 )
            end
         elseif type( v ) == 'string' then
            io.write( string.rep( ' ', indent ), string.format( '  %s : %s\n', k, v ) )
         elseif type( v ) == 'number' then
            io.write( string.rep( ' ', indent ), string.format( '  %s : %f\n', k, v ) )
       end
    end
  end
end

local function test_parser( program )
  lexer.init( program )
  --lexer.dump_tokens()
  parser.init( lexer, report_error )
  local tree = parser.parse()
  dump_table( tree )
end

local function test_interp( program )
   lexer.init( program )
   parser.init( lexer, report_error )
   interpreter.init()
   local tree = parser.parse()
   return interpreter.interpret( tree )
end

do
  local res = test_interp( [[
var greet = function( name ) { print( "Greetings, ", name, "\n" ); };
var foo = function( blah ) { print( "foo ", blah ); println( " THIS IS A TEST" ); };
var a = 42 * 3;
var str = "Hello, world!\n";
println( "A is ", a );
a = a + 7;
println( "Now A is ", a );
foo( a );
greet( "Timo" );
print( str );
var _ = function( f, t ) { f( t ); };
_( foo, "thingy" );
var abc = function() { return 42; };
println( "abc() + a = ", abc() + a );
]] )
end
