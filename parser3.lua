-- port of the following from javascript to lua
-- http://javascript.crockford.com/tdop/tdop.html

-- a parser for Douglas Crockford's "Simplified JavaScript"

-- current scope object
local scope = {}
-- prototype for all scope objects
local original_scope = {}
-- source of tokens
local m_token_source = nil
-- function for reporting errors
local m_error_reporter = nil
-- current token
local token = nil

function init( token_source, error_reporter )
   m_token_source = token_source
   m_error_reporter = error_reporter
end

local function nxt()
   token = m_token_source.token()
end

-- the global symbol table
local symbol_table = {}

-- the prototype symbol
local original_symbol = {
   nud = function( self ) error( 'Undefined NUD' ) end,
   led = function( self, left ) error( 'Missing operator (LED)' ) end
}

local symbol_mt = { __index = original_symbol }

-- symbol ID and binding power
local function symbol( symid, bp )
   local s = symbol_table[ symid ]
   bp = bp or 0
   if s then
      -- adjust binding power
      if bp >= s.lbp then
    s.lbp = bp
      end
   else
      -- create symbol
      s = { id = symid, value = symid, lbp = bp }
      setmetatable( s, symbol_mt )
      symbol_table[ symid ] = s
   end
   return s
end

-- create a bunch of initial symbols
do
   symbol( ':' )
   symbol( ';' )
   symbol( ',' )
   symbol( ')' )
   symbol( ']' )
   symbol( '}' )
   symbol( 'else' )
   symbol( '(end)' )
   symbol( '(name)' )
end

-- advance to the next token, possibly ensuring
-- that it matches an expected one
local function advance( id )
   local a, o, t, v
   if id and token.id ~= id then
      error( 'Expected ' .. id .. '.' )
   end

   nxt()
   if token.id == '(end)' then
      return
   end

   t = token
   v, a = t.value, t.type

   if a == 'name' then
      o = scope:find( v )
   elseif a == 'operator' then
      o = symbol_table[ v ]
      if not o then
    error( 'Unknown operator' )
      end
   elseif a == 'string' or a == 'number' then
      a = 'literal'
      o = symbol_table[ '(literal)' ]
   else
      error( string.format( 'Unexpected token (value=%s,type=%s)', tostring( v ), tostring( a ) ) )
   end

   token = { value = v, arity = a }
   setmetatable( token, { __index = o } )
   return token
end

-- layer a new scope on top of the current scope
function scope:new_scope()
   local s = scope

   -- set original_scope as prototype
   setmetatable( scope, self )
   self.__index = original_scope

   scope.def = {}
   scope.parent = s
   return scope
end

-- create original scope (also its own prototype)
do
   original_scope = scope:new_scope()
   original_scope.parent = nil
end

-- used to define a new variable in scope
-- error() if variable already defined in scope
-- or if the name is a reserved word
function original_scope:define( n )
   local t = self.def[ n.value ]
   if type( t ) == 'table' then
      error( t.reserved and 'Already reserved' or 'Already defined' )
   end
   self.def[ n.value ] = n
   n.reserved = false
   n.nud      = function( self ) return self end
   n.led      = nil
   n.std      = nil
   n.lbp      = 0
   n.scope    = scope
   return n
end

-- find the definition of a name.  Goes back up the
-- chain through parent scopes to symbol table. returns
-- symbol_table[ '(name)' ] if it cannot find a definition
function original_scope:find( n )
   local e, o = self, nil
   while true do
      o = e.def[ n ]
      if o and type( o ) ~= 'function' then
         return e.def[ n ]
      end

      e = e.parent
      if not e or e == e.parent then
         o = symbol_table[ n ]
         if o and type( o ) ~= 'function' then
            return o
         else
            return symbol_table[ '(name)' ]
         end
      end
   end
end

-- closes a scope, giving focus back to the parent
function original_scope:pop()
   scope = self.parent
end

-- reserve a name in the current scope
function original_scope:reserve( n )
   if n.arity ~= 'name' or n.reserved then
      return
   end
   local t = self.def[ n.value ]
   if t then
      if t.reserved then
    return
      end
      if t.arity == 'name' then
    error( 'Already defined' )
      end
   end
   self.def[ n.value ] = n
   n.reserved = true
end

-- parse an expression
-- rbp is 'right binding power',
-- or how aggressively it binds to the tokens on its right
local function expression( rbp )
   local left, t = nil, token
   advance()
   left = t:nud()
   while rbp < token.lbp do
      t = token
      advance()
      left = t:led( left )
   end
   return left
end

-- define operators

-- infix operators
local function infix( id, bp, led )
   local s = symbol( id, bp )
   s.led = led or
      function( self, left )
          self.first = left
          self.second = expression( bp )
          self.arity = 'binary'
          return self
      end
   return s
end

infix( '+', 50 )
infix( '-', 50 )
infix( '*', 60 )
infix( '/', 60 )

infix( '===', 40 )
infix( '!==', 40 )
infix( '<',   40 )
infix( '<=',  40 )
infix( '>',   40 )
infix( '>=',  40 )

infix( '?', 20,
       function( self, left )
     self.first = left
     self.second = expression( 0 )
     advance( ':' )
     self.third = expression( 0 )
     self.arity = 'ternary'
     return self
       end
)

infix( '.', 80,
       function( self, left )
     self.first = left
     if token.arity ~= 'name' then
        error( 'Expected a property name' )
     end
     token.arity = 'literal'
     self.second = token
     self.arity = 'binary'
     advance()
     return self
       end
)

infix( ']', 80,
       function( self, left )
     self.first = left
     self.second = expression( 0 )
     self.arity = 'binary'
     advance( ']' )
     return self
       end
)

-- infix operators, right associative
local function infixr( id, bp, led )
   local s = symbol( id, bp )
   s.led = led or
      function( self, left )
    self.first = left
    self.second = expression( bp - 1 )
    self.arity = 'binary'
    return self
      end
   return s
end

infixr( '&&', 30 )
infixr( '||', 30 )

-- prefix operators
local function prefix( id, nud )
   local s = symbol( id )
   s.nud = nud or
      function( self )
       scope:reserve( self )
       self.first = expression( 70 )
       self.arity = 'unary'
       return self
      end
   return s
end

prefix( '-' )
prefix( '!' )
prefix( 'typeof' )

prefix( '(',
   function ()
      local e = expression( 0 )
      advance( ')' )
      return e
   end
)

-- assignment operators
local function assignment( id )
   return infixr( id, 10,
        function( self, left )
           if left.id ~= '.' and left.id ~= '[' and left.arity ~= 'name' then
         error( 'Bad lvalue' )
           end
           self.first = left
           self.second = expression( 9 )
           self.assignment = true
           self.arity = 'binary'
           return self
        end
   ) -- infixr( ...
end

assignment( '=' )
assignment( '+=' )
assignment( '-=' )

-- constant values
local function constant( s, v )
   local x = symbol( s )
   x.nud = function( self )
      scope:reserve( self )
      self.value = symbol_table[ self.id ].value
      self.arity = 'literal'
      return self
   end
   x.value = v
   return x
end

constant( 'true', true )
constant( 'false', false )
constant( 'null', nil )

constant( 'pi', 3.141592653589793 )

-- prototype of all string and number literal tokens
-- 'nud' returns the token itself
symbol( '(literal)' ).nud = function( self ) return self end
symbol( '(name)' ).nud = function( self ) return self end

-- std = Statement Denotation
local function statement()
   local n, v = token, nil

   if n.std then
      advance()
      scope:reserve( n )
      return n:std()
   end
   v = expression( 0 )
   if not v.assignment and v.id ~= '(' then
      error( 'Bad expression statement' )
   end
   advance( ';' )
   return v
end

local function statements()
   local a, s = {}, nil

   -- gather up as many statements as possible
   while true do
      if token.id == '}' or token.id == '(end)' then
         break
      end

      s = statement()
      if s then
         table.insert( a, s )
      end
   end

   -- figure out what to return
   if #a == 0 then
      return nil
   elseif #a == 1 then
      return a[ 1 ]
   else
      return a
   end
end

-- define statements
local function stmt( s, f )
   local x = symbol( s )
   x.std = f
   return x
end

stmt( '{',
      function ( self )
    scope:new_scope()
    local a = statements()
    advance( '}' )
    scope:pop()
    return a
      end
)

local function block()
   local t = token
   advance( '{' )
   return t:std()
end

stmt( 'var',
      function( self )
          local a, n, t = {}, nil, nil
          while true do
             n = token
             if n.arity ~= 'name' then
                error( 'Expected a new variable name' )
             end
             scope:define( n )
             advance()
             if token.id == '=' then
                t = token
                advance( '=' )
                t.first = n
                t.second = expression( 0 )
                t.arity = 'binary'
                table.insert( a, t )
             end
             if token.id ~= ',' then
                break
             end
             advance( ',' )
          end
          advance( ';' )

          if #a == 0 then
             return nil
          elseif #a == 1 then
             return a[ 1 ]
          else
             return a
          end
      end
)

stmt( 'while',
      function ( self )
    advance( '(' )
    self.first = expression( 0 )
    advance( ')' )
    self.second = block()
    self.arity = 'statement'
    return self
      end
)

stmt( 'if',
      function( self )
    advance( '(' )
    self.first = expression( 0 )
    advance( ')' )
    self.second = block()
    if token.id == 'else' then
       scope:reserve( token )
       advance( 'else' )
       self.third = token.id == 'if' and statement() or block()
    else
       self.third = nil
    end
    self.arity = 'statement'
    return self
      end
)

stmt( 'break',
      function( self )
    advance( ';' )
    if token.id ~= '}' then
       error( 'Unreachable statement' )
    end
    self.arity = 'statement'
    return self
      end
)

stmt( 'return',
      function( self )
    if token.id ~= ';' then
       self.first = expression( 0 )
    end
    advance( ';' )
    if token.id ~= '}' then
       error( 'Unreachable statement' )
    end
    self.arity = 'statement'
    return self
      end
)

prefix( 'function',
   function( self )
      local a = {}
      scope:new_scope()
      if token.arity == 'name' then
         scope:define( token )
         self.name = token.value
         advance()
      end
      advance( '(' )
      if token.id ~= ')' then
         while true do
       if token.arity ~= 'name' then
          error( 'Expected a parameter name' )
       end
       scope:define( token )
       table.insert( a, token )
       advance()
       if token.id ~= ',' then
          break
       end
       advance( ',' )
         end
      end
      self.first = a
      advance( ')' )
      advance( '{' )
      self.second = statements()
      advance( '}' )
      self.arity = 'function'
      scope:pop()
      return self
   end
)

infix( '(', 80,
       function( self, left )
           local a = {}
           if left.id == '.' or left.id == '[' then
              self.arity = 'ternary'
              self.first = left.first
              self.second = left.second
              self.third = a
           else
              self.arity = 'binary'
              self.first = left
              self.second = a
              if( left.arity ~= 'unary' or left.id ~= 'function' ) and
            left.arity ~= 'name' and left.id ~= '(' and
              left.id ~= '&&' and left.id ~= '||' and left.id ~= '?' then
            error( 'Expected a variable name' )
              end
           end
           if token.id ~= ')' then
              while true do
            table.insert( a, expression( 0 ) )
            if token.id ~= ',' then
               break
            end
            advance( ',' )
              end
           end
           advance( ')' )
           return self
       end
)

symbol( 'this' ).nud =
   function( self )
      scope:reserve( self )
      self.arity = 'this'
   end

prefix( '[',
   function( self )
      local a = {}
      if token.id ~= ']' then
         while true do
       table.insert( a, expression( 0 ) )
       if token.id ~= ',' then
          break
       end
       advance( ',' )
         end
      end
      advance( ']' )
      self.first = a
      self.arity = 'unary'
      return self
   end
)

prefix( '{',
   function( self )
      local a = {}
      if token.id ~= '}' then
         while true do
       local n = token
       if n.arity ~= 'name' and n.arity ~= 'literal' then
          error( 'Bad key' )
       end
       advance()
       advance( ':' )
       local v = expression( 0 )
       v.key = n.value
       table.insert( a, v )
       if token.id ~= ',' then
          break
       end
       advance( ',' )
         end
      end
      advance( '}' )
      self.first = a
      self.arity = 'unary'
      return self
   end
)

function parse()
   scope:new_scope()
   advance()
   local s = statements()
   scope:pop();
   advance( '(end)' )
   return s
end

-- return public interface
-- create the naked 'module'
local parser = {
   init = init,
   parse = parse
}
parser.__index = parser

return parser
