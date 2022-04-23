local function ProfileFunction(Func: ((...any) -> (...any)), Tag: string)
    return function(...)
        debug.profilebegin(Tag)
        local Result = Func(...)
        debug.profileend()
        return Result
    end
end

return ProfileFunction