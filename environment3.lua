-- environment3.lua

env = {}
env.__index = env

function env:create()
   local e = {}
   setmetatable( e, env ) -- new environments inherit env's methods
   e.bindings = {}
   e.parent = self
   return e
end

function env:pop()
   local p = self.parent
   if not p then
      error( 'Popped too many environments' )
   end

   return p
end

function env:bind( name, value )
   self.bindings[ name ] = value
end

function env:find( name )
   local e, binding = self, nil

   repeat
      binding = e.bindings[ name ]
      if binding then break end
      e = e.parent
   until e == nil or e == e.parent

   if not binding then
      error( string.format( 'Unable to find binding %s', name ) )
   end

   return binding
end
