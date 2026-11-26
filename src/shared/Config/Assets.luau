--!strict
local TableUtil = require(script.Parent.Parent.Util.TableUtil)

-- TODO: Populate IDs after the original assets are published.
return TableUtil.deepFreeze({
	models = {} :: { [string]: number },
	animations = {} :: { [string]: number },
	sounds = {} :: { [string]: number },
	vfx = {} :: { [string]: number },
})
