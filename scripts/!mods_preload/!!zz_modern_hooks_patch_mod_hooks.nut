if (!("mods_hookExactClass" in this.getroottable()))
	return;
::Hooks.inform("=================Patching Modding Script Hooks=================")
::mods_hookExactClass = function( name, func )
{
	::Hooks.__rawHook(::Hooks.getMod("mod_hooks"), "scripts/" + name, func);
}

local lastRegistered = null;
::mods_registerMod = function( codeName, version, friendlyName = null, extra = null )
{
	lastRegistered = codeName;
	::Hooks.__unverifiedRegister(codeName, version, friendlyName == null ? codeName : friendlyName, extra);
}

foreach (mod in ::mods_getRegisteredMods())
{
	local meta = clone mod;
	delete meta.Name;
	delete meta.Version;
	delete meta.FriendlyName;
	::mods_registerMod(mod.Name, mod.Version, mod.FriendlyName, meta);
}

local g_exprRe = regexp("^([!<>])?(\\w+)(?:\\(([<>]=?|=|!=)?([\\w\\.\\+\\-]+)\\))?$");
local function inverter(_operator)
{
	switch (_operator)
	{
		case "=":
		case null:
			return "!";
		case "!":
			return "=";
		case ">=":
			return "<";
		case ">":
			return "<=";
		case "<=":
			return ">";
		case "<":
			return ">=";
	}
}

::mods_queue = function( codeName, expr, func )
{
	if (codeName == null)
		codeName = lastRegistered;
	if (!::Hooks.hasMod(codeName))
		::Hooks.errorAndThrow(format("Mod %s is trying to queue without registering first", codeName));

	// parse expression using mod_hooks function
	local match = function(s,m,i) {
		local m = m[i];
		local len = s.len();
		local found = m.begin >= 0 && m.end > 0 && m.begin < len && m.end <= len;
		return found ? s.slice(m.begin, m.end) : null
	};
	if (expr == "" || expr == null)
		expr = []
	else
		expr = split(expr, ",");
	for(local i = 0; i < expr.len(); ++i)
	{
		local e = strip(expr[i]), m = g_exprRe.capture(e);
		if (m == null)
			throw "Invalid queue expression '" + e + "'.";
		expr[i] = { op = m[1].end != 0 ? e[0] : null, modName = match(e, m, 2), verOp = match(e, m, 3), version = match(e, m, 4) };
	}

	local mod = ::Hooks.getMod(codeName);
	local compatibilityData = {
		Require = [mod],
		ConflictWith = [mod]
	};
	local loadOrderData = [mod];
	// now convert into modern_hooks
	local splitExpr = [];
	foreach (expression in expr)
	{
		if ([null, '!'].find(expression.op) == null && expression.verOp != null)
		{
			splitExpr.push({
				op = expression.op,
				modName = expression.modName,
				verOp = null,
				version = null,
			});
			splitExpr.push({
				op = null,
				modName = expression.modName,
				verOp = expression.verOp,
				version = expression.version
			});
			continue;
		}
		splitExpr.push(expression)
	}

	foreach (expression in splitExpr)
	{
		local expressionInfo = expression.modName;
		if (expression.verOp != null)
			expressionInfo += format(" %s %s",expression.verOp, expression.version);
		local invert = false;
		local requirement = null;
		switch (expression.op)
		{
			case null:
				requirement = true;
				compatibilityData.Require.push(expressionInfo);
				loadOrderData.push(">" + expression.modName);
				break;
			case '!':
				requirement = false;
				compatibilityData.ConflictWith.push(expressionInfo);
				break;
			case '<':
				invert = true;
				loadOrderData.push("<" + expression.modName);
				break;
			case '>':
				invert = true;
				loadOrderData.push(">" + expression.modName);
				break;
		}
		if (expression.version == null)
			continue;
		if (invert)
		{
			compatibilityData.ConflictWith.push(expression.modName);
			requirement = false;
			expression.verOp = inverter(expression.verOp)
		}
		local currentArray = compatibilityData[requirement ? "Require" : "ConflictWith"];
		local currentMod = currentArray[currentArray.len()-1];
		if (expression.verOp == null)
			expression.verOp = "=";
		currentMod += " " + expression.verOp + " " + expression.version;
	}
	mod.require.acall(compatibilityData.Require);
	mod.conflictWith.acall(compatibilityData.ConflictWith);
	loadOrderData.push(func);
	mod.queue.acall(loadOrderData);
}

::mods_getRegisteredMod = function( _modID )
{
	if (!::Hooks.hasMod(_modID))
		return null;

	local mod = ::Hooks.getMod(_modID);
	local meta = clone mod.getMetaData();
	meta.Name <- mod.getID();
	if (typeof mod.getVersion() == "float")
	{
		meta.Version <- mod.getVersion();
	}
	else
	{
		meta.Version <- 2147483647;
		if ("MSU" in this.getroottable()) // patch for old MSU, might remove later
		{
			meta.SemVer <- ::MSU.SemVer.getTable(mod.getVersionString());
		}
	}
	meta.FriendlyName <- mod.getName();
	return meta;
}

::mods_getRegisteredMods = function()
{
	local mods = [];
	foreach (mod in ::Hooks.getMods())
	{
		mods.push(::mods_getRegisteredMod(mod.getID()));
	}
	return mods;
}

::_mods_runQueue = @()null; // fix syntax highlighter bug here
