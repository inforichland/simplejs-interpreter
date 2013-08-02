-- Produce an array of simple token objects from a string.
-- A simple token object contains these members:
--      type: 'name', 'string', 'number', 'operator'
--      value: string or number value of the token
--      from: index of first character of the token
--      to: index of the last character + 1

-- Lexical analyzer
local string = require( 'string' )

-- module-level variables
local pos = 1
local buf = nil
local buflen = 0

-- allow "foo"[ 1 ] -type indexing for strings
getmetatable( '' ).__index = function( str, i )
  if type( i ) == 'number' then
    return string.sub( str, i, i )
  else
    return string[ i ]
  end
end

-- operator table
local optable = {
    ['+']  =  'PLUS',
    ['-']  =  'MINUS',
    ['*']  =  'MULTIPLY',
    ['.']  =  'PERIOD',
    ['\\'] =  'BACKSLASH',
    [':']  =  'COLON',
    ['%']  =  'PERCENT',
    ['|']  =  'PIPE',
    ['!']  =  'EXCLAMATION',
    ['?']  =  'QUESTION',
    ['#']  =  'POUND',
    ['&']  =  'AMPERSAND',
    [';']  =  'SEMI',
    [',']  =  'COMMA',
    ['(']  =  'L_PAREN',
    [')']  =  'R_PAREN',
    ['<']  =  'L_ANG',
    ['>']  =  'R_ANG',
    ['{']  =  'L_BRACE',
    ['}']  =  'R_BRACE',
    ['[']  =  'L_BRACKET',
    [']']  =  'R_BRACKET',
    ['=']  =  'EQUALS'
}

-- set input
function set_input( buffer )
  pos = 1
  buf = buffer
  buflen = #buffer
end

-- create new instance (constructor)
function init( buffer )
  -- initialization
  set_input( buffer )
end

-- helpful utilities
local function isnewline( c ) return c == '\r' or c == '\n' end
local function isdigit( c ) return c >= '0' and c <= '9' end
local function isalpha( c )
  return ( c >= 'a' and c <= 'z' ) or
      ( c >= 'A' and c <= 'Z' ) or
      c == '_' or c == '$'
end
local function isalphanum( c ) return isdigit( c ) or isalpha( c ) end

-- process a number from the input stream
local function process_number()
  local endpos = pos + 1
  -- scan for numbers
  while ( endpos <= buflen ) and ( isdigit( buf[ endpos ] ) ) do
    endpos = endpos + 1
  end

  local tok = {
    type = 'number',
    value = tonumber( buf:sub( pos, endpos - 1 ) ),
    pos = pos
  }

  pos = endpos
  return tok
end

-- process a comment from the input stream
local function process_comment()
  local endpos = pos + 2
  -- scan for end of comment
  while endpos <= buflen and not isnewline( buf[ endpos ] ) do endpos = endpos + 1 end

  pos = endpos + 1
end

-- process an identifier from the input stream
local function process_identifier()
  local endpos = pos + 1
  -- scan for end of identifier
  while endpos <= buflen and isalphanum( buf[ endpos ] ) do endpos = endpos + 1 end
  local v = buf:sub( pos, endpos - 1 )

  local tok = {
    type = 'name',
    value = v,
    pos = pos
  }

  pos = endpos
  return tok
end

-- process a string from the input stream
local function process_quote()
  local end_index = buf:find( '"', pos + 1 )

  if end_index == nil then
    error( string.format( 'Unterminated quote at %d' + pos ) )
  else
    local tok = {
      [ 'type' ] = 'string',
      value = buf:sub( pos + 1, end_index - 1 ),
      pos = pos
    }

    pos = end_index + 1
    return tok
  end
end

-- skip whitespace
local function skip_whitespace()
  while pos <= buflen do
    local c = buf[ pos ]
    if c == ' ' or c == '\t' or c == '\n' or c == '\r' then pos = pos + 1 else break end
  end
end

-- get the next token from the current buffer.
local function token()
  skip_whitespace()

  -- check for EOF
  if( pos > buflen ) then return { id = '(end)' } end
  -- get current character
  local c = buf[ pos ]

  -- / must be treated specially, as it is both divide and part of 'begin comment'
  if c == '/' then
    local next_c = buf[ pos + 1 ]
    if next_c == '/' then
      process_comment() -- ignore comment
      return token() -- get next token
    else
      local ret = { [ 'type' ] = 'operator', value = '/', pos = pos, id = '/' }
      pos = pos + 1
      return ret
    end
  elseif c == '*' then
    local next_c = buf[ pos + 1 ]
    if next_c == '*' then -- exponentiation
      local ret = { [ 'type' ] = 'operator', value = '**', pos = pos, id = '**' }
      pos = pos + 2
      return ret
    else
      local ret = { [ 'type' ] = 'operator', value = '*', pos = pos, id = '*' }
      pos = pos + 1
      return ret
    end
  else -- not divide, so look it up
    local op = c
    -- valid operator
    if optable[ c ] then
      local ret = { [ 'type' ] = 'operator', value = op, pos = pos, id = op }
      pos = pos + 1
      return ret
    else
      -- not an operator, beginning of another token
      if isalpha( c ) then
        return process_identifier()
      elseif isdigit( c ) then
        return process_number()
      elseif( c == '"' ) then
        return process_quote()
      else
        error( string.format( 'Token error at %d', pos ) )
      end
    end
  end
end

-- return a table of all tokens
local function tokenize()
  local tokens, t, pos = {}, token(), 1

  while t.id ~= '(end)' do
    tokens[ pos ] = t
    pos = pos + 1
    t = token()
  end

  return tokens
end

-- DEBUG
function dump_tokens()
   for _, v in ipairs( tokenize() ) do
      io.write( string.format( 'Type (%s):    %s  @  %d\n', v.type, v.value, v.pos ) )
   end
end

-- return public interface
-- create the naked 'module'
local lexer = {
  init = init,
  tokenize = tokenize,
  token = token,
  set_input = set_input,
  dump_tokens = dump_tokens
}

-- allow calling lexer (to simulate an anonymous constructor)
setmetatable( lexer, {
  __call = function( cls, ... )
    return cls.set_input( ... )
  end,
})
lexer.__index = lexer

return lexer
