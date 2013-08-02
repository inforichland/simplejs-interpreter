-- scope.lua

scope = {}
scope.__index = scope

local m_symbol_table = nil
local m_scope = nil

function scope.init( symtab )
  m_symbol_table = symtab
  m_scope = scope.create()
end

function scope.create()
  local sc = {}
  setmetatable( sc, scope )
  sc.def = {}
  sc.parent = scope
  return sc
end

function scope.get_current()
  return m_scope
end

function scope:define( n )
  local t = self.def[ n.value ]
  if t ~= nil then
    error( 'Already reserved' and t.reserved or 'Already defined' )
  end
  self.def[ n.value ] = n
  n.reserved = false
  n.nud = function() return n end
  n.led = nil
  n.std = nil
  n.lbp = 0
  n.scope = m_scope
  return n
end

function scope:find( n )
  local e, o = self, nil
  while true do
    o = e.def[ n ]
    if o and type( o ) ~= 'function' then
      return e.def[ n ]
    end

    if e == e.parent then
      o = m_symbol_table[ n ]
      return o and type( o ) ~= 'function' and o or m_symbol_table[ "(name)" ]
    end
    e = e.parent
  end
end
  
function scope:pop()
  m_scope = self.parent
end

function scope:reserve( n )
  if n.arity ~= 'name' or n.reserved then return end
  local t = self.def[ n.value ]
  if t then
    if t.reserved then return end
    if t.arity == 'name' then error( 'Already defined' ) end
  end
  self.def[ n.value ] = n
  n.reserved = true
end
