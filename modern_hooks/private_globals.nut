::Hooks.__getNameForQueueBucket <- function( _queueBucketID ) // not a fan of this function but without MSU enums this is a pain
{
	foreach (key, val in ::Hooks.QueueBucket)
	{
		if (_queueBucketID == val)
			return key;
	}
}

::Hooks.__msu_regexMatch <- function( _capture, _string, _group )
{
	return _capture[_group].end > 0 && _capture[_group].begin < _string.len() ? _string.slice(_capture[_group].begin, _capture[_group].end) : null;
}

::Hooks.__msu_SemVer_isSemVer <- function( _string )
{
	if (typeof _string != "string") return false;
	return ::Hooks.__SemVerRegex.capture(_string) != null;
}

::Hooks.__validateModCompatibility <- function()
{
	local compatErrors = [];
	foreach (mod in this.getMods())
	{
		foreach (compatibilityData in mod.getCompatibilityData())
		{
			local result = compatibilityData.validate(this.getMods());
			if (result == ::Hooks.CompatibilityCheckResult.Success)
				continue;
			compatErrors.push({
				Source = mod,
				Target = compatibilityData,
				Reason = result
			});
		}
	}
	if (compatErrors.len() == 0)
		return true;
	foreach (error in compatErrors)
	{
		switch (error.Reason)
		{
			case ::Hooks.CompatibilityCheckResult.ModMissing:
				local name = error.Target.getModID() in ::Hooks.CachedModNames ? ::Hooks.CachedModNames[error.Target.getModID()] : error.Target.getModName();
				::Hooks.error(format("%s (%s) requires %s (%s)%s", error.Source.getID(), error.Source.getName(), error.Target.getModID(), name, error.Target.getFormattedDetails()));
				break;
			case ::Hooks.CompatibilityCheckResult.ModPresent:
				local mod = ::Hooks.getMod(error.Target.getModID());
				::Hooks.error(format("%s (%s) is incompatible with %s (%s)%s", error.Source.getID(), error.Source.getName(), mod.getID(), mod.getName(), error.Target.getFormattedDetails()));
				break;
			case ::Hooks.CompatibilityCheckResult.TooSmall:
				local mod = ::Hooks.getMod(error.Target.getModID());
				::Hooks.error(format("%s (%s) version %s is outdated for %s (%s), which requires versions %s", mod.getID(), mod.getName(), mod.getVersionString(), error.Source.getID(), error.Source.getName(), error.Target.getErrorString()))
				break;
			case ::Hooks.CompatibilityCheckResult.TooBig:
				local mod = ::Hooks.getMod(error.Target.getModID());
				::Hooks.error(format("%s (%s) version %s is too new for %s (%s), which requires versions %s", mod.getID(), mod.getName(), mod.getVersionString(), error.Source.getID(), error.Source.getName(), error.Target.getErrorString()))
				break;
			case ::Hooks.CompatibilityCheckResult.Incorrect:
				local mod = ::Hooks.getMod(error.Target.getModID());
				::Hooks.error(format("%s (%s) version %s is wrong for %s (%s), which requires (a) version %s", mod.getID(), mod.getName(), mod.getVersionString(), error.Source.getID(), error.Source.getName(), error.Target.getErrorString()))
				break;
		}
	}
	::Hooks.errorAndQuit("Errors occured when validating mod compatibility, the game was therefore not loaded correctly");
	return false;
}

::Hooks.__unverifiedRegister <- function( _modID, _version, _modName, _metaData = null )
{
	if (_metaData == null)
		_metaData = {};
	if (_modID in this.Mods)
	{
		::Hooks.errorAndThrow(format("Mod %s (%s) version %s is trying to register twice", _modID, _modName, _version.tostring()))
	}
	local mod = ::Hooks.SQClass.Mod(_modID, _version, _modName, _metaData);
	this.Mods[_modID] <- mod;
	this.OrderedMods.push(mod);
	::Hooks.inform(format("Modern Hooks registered [emph]%s[/emph] (%s) version [emph]%s[/emph]", this.Mods[_modID].getName(), this.Mods[_modID].getID(), this.Mods[_modID].getVersion().tostring()))
	return this.Mods[_modID];
}

::Hooks.__sortQueue <- function( _queuedFunctions )
{
	return ::Hooks.ModHooksQueueGraph(_queuedFunctions).getSorted();
}

::Hooks.__executeQueuedFunctions <- function( _queuedFunctions )
{
	local root = getroottable();
	foreach (queuedFunction in _queuedFunctions)
	{
		local mod = queuedFunction.getMod();
		local versionString = typeof mod.getVersion() == "float" ? mod.getVersion().tostring() : mod.getVersion().getVersionString();
		::Hooks.inform(format("Executing queued function [emph]%i %s[/emph] for [emph]%s[/emph] (%s) version %s.", queuedFunction.getFunctionID(), queuedFunction.getDetailsString(), mod.getName(), mod.getID(), versionString));
		try
		{
			queuedFunction.getFunction().call(root);
		}
		catch (error)
		{
			::Hooks.errorAndQuit(format("Mod %s (%s) version %s had an error (%s) during queue function %i %s.", mod.getID(), mod.getName(), versionString, error, queuedFunction.getFunctionID(), queuedFunction.getDetailsString()));
		}
	}
}

::Hooks.__runQueue <- function()
{
	this.__validateModCompatibility();

	local buckets = {}; // I hate how I've had to do these buckets without MSU enums
	foreach (mod in this.OrderedMods)
	{
		foreach (func in mod.getQueuedFunctions())
		{
			if (!(func.getBucket() in buckets))
				buckets[func.getBucket()] <- [];
			buckets[func.getBucket()].push(func);
		}
	}
	local bucketTypes = [];
	foreach (bucketType in ::Hooks.QueueBucket)
		bucketTypes.push(bucketType);
	bucketTypes.sort();
	foreach (idx, bucketType in bucketTypes)
	{
		if (!(bucketType in buckets))
			continue;
		buckets[bucketType] = this.__sortQueue(buckets[bucketType]);
	}

	// by definition that bucket is handled later
	if (::Hooks.QueueBucket.AfterHooks in buckets)
	{
		::Hooks.AfterHooksBucket = buckets[::Hooks.QueueBucket.AfterHooks];
		delete buckets[::Hooks.QueueBucket.AfterHooks];
	}
	if (::Hooks.QueueBucket.FirstWorldInit in buckets)
	{
		::Hooks.FirstWorldInitBucket = buckets[::Hooks.QueueBucket.FirstWorldInit];
		delete buckets[::Hooks.QueueBucket.FirstWorldInit];
	}

	foreach (bucketType in bucketTypes)
	{
		if (!(bucketType in buckets))
			continue;
		::Hooks.inform(format("-----------------Running queue bucket [emph]%s[/emph]-----------------", ::Hooks.__getNameForQueueBucket(bucketType)));
		this.__executeQueuedFunctions(buckets[bucketType]);
	}
}

::Hooks.__runAfterHooksQueue <- function()
{
	if (::Hooks.AfterHooksBucket == null)
		return;
	::Hooks.inform(format("-----------------Running queue bucket [emph]%s[/emph]-----------------", ::Hooks.__getNameForQueueBucket(::Hooks.QueueBucket.AfterHooks)));
	this.__executeQueuedFunctions(::Hooks.AfterHooksBucket);
}

::Hooks.__registerClass <- function( _src, _prototype )
{
	this.__initClass(_src);
	this.BBClass[_src].Prototype = _prototype;
	this.__registerForAncestorTreeHooks(_prototype, _src);
}

::Hooks.__initClass <- function( _src )
{
	if (!(_src in this.BBClass))
		this.BBClass[_src] <- {
			TreeHooks = [],
			RawHooks = [],
			NativeHooks = [],
			// MetaHooks = [] to do later
			Descendants = [],
			Prototype = null,
			Processed = false
		};
}

::Hooks.__registerForAncestorTreeHooks <- function( _prototype, _src )
{
	local src = _src;
	local p = _prototype;
	do
	{
		if (src in this.BBClass && this.BBClass[src].TreeHooks.len() != 0)
			this.BBClass[src].Descendants.push(_prototype);
	}
	while ("SuperName" in p && (p = p[p.SuperName]) && (src = ::IO.scriptFilenameByHash(p.ClassNameHash)))
}

::Hooks.__rawHook <- function( _mod, _src, _func )
{
	this.__initClass(_src);
	this.BBClass[_src].RawHooks.push({
		Mod = _mod,
		hook = _func
	});
}

::Hooks.__hook <- function( _mod, _src, _func )
{
	::Hooks.__rawHook(_mod, _src, function(p) {
		_func(::Hooks.__Q.Q(_mod, _src, p));
	});
}

::Hooks.__rawHookTree <- function( _mod, _src, _func )
{
	this.__initClass(_src);
	this.BBClass[_src].TreeHooks.push({
		Mod = _mod,
		hook = _func
	});
}

::Hooks.__hookTree <- function( _mod, _src, _func )
{
	::Hooks.__rawHookTree(_mod, _src, function(p) {
		_func(::Hooks.__Q.QTree(_mod, _src, p, ::IO.scriptFilenameByHash(p.ClassNameHash)));
	});
}

::Hooks.__processRawHooks <- function( _src )
{
	local p = this.BBClass[_src].Prototype;
	local root = getroottable();
	foreach (hookInfo in this.BBClass[_src].RawHooks)
	{
		try
		{
			hookInfo.hook.call(root, p);
		}
		catch (error)
		{
			local versionString = typeof hookInfo.Mod.getVersion() == "float" ? hookInfo.Mod.getVersion().tostring() : hookInfo.Mod.getVersion().getVersionString();
			::Hooks.errorAndQuit(format("Mod %s (%s) version %s had an error (%s) during its hook on bb class %s.", hookInfo.Mod.getID(), hookInfo.Mod.getName(), versionString, error, _src));
		}
	}
	foreach (hookInfo in this.BBClass[_src].NativeHooks)
	{
		try
		{
			hookInfo.hook.call(root, p);
		}
		catch (error)
		{
			local versionString = typeof hookInfo.Mod.getVersion() == "float" ? hookInfo.Mod.getVersion().tostring() : hookInfo.Mod.getVersion().getVersionString();
			::Hooks.errorAndQuit(format("Mod %s (%s) version %s had an error (%s) during its native hook on bb class %s.", hookInfo.Mod.getID(), hookInfo.Mod.getName(), versionString, error, _src));
		}
	}
	this.BBClass[_src].Processed = true;
}

::Hooks.__finalizeHooks <- function()
{
	local root = getroottable();
	foreach (src, bbclass in this.BBClass)
	{
		// normal hook logic
		if (!bbclass.Processed)
		{
			if (bbclass.Prototype == null)
			{
				::Hooks.error(format("%s was never proceessed for hooks", src));
				continue;
			}
			this.__processRawHooks(src);
		}

		// leaf hook logic
		foreach (p in bbclass.Descendants)
			foreach (hookInfo in bbclass.TreeHooks)
			{
				try
				{
					hookInfo.hook.call(root, p);
				}
				catch (error)
				{
					local versionString = typeof hookInfo.Mod.getVersion() == "float" ? hookInfo.Mod.getVersion().tostring() : hookInfo.Mod.getVersion().getVersionString();
					::Hooks.errorAndQuit(format("Mod %s (%s) version %s had an error (%s) during its tree hook on bb class %s.", hookInfo.Mod.getID(), hookInfo.Mod.getName(), versionString, error, _src));
				}
			}
	}
}

::Hooks.__getCachedNameForID <- function( _id )
{
	return _id in ::Hooks.CachedModNames ? ::Hooks.CachedModNames[_id] : _id;
}

::Hooks.__debughook <- function( _eventType, _src, _line, _funcName )
{
	if (_eventType == 'r' && _funcName == "main")
	{
		// would be great if this block could be improved with something like ::seterrorhandler
		// but that doesn't seem to do anything in our squirrel build.
		// The issue right now is that the only information catch receives is the error code,
		// it doesn't get any information about where that error occured
		// this means that instead any code executed by hooks needs to use intensive validation
		// and maybe its own try/catch blocks to make it easier to identify the source of the error
		try
		{
			// fix path
			_src = ::String.replace(_src.slice(0, -4), "\\", "/");
			local i = -8;
			for (local j; (j = _src.find("scripts/", i+8)) != null; i = j) { }
			if (i > 0) _src = _src.slice(i);

			// check if bb class
			local className = split(_src, "/").pop();
			local fileScope = ::getstackinfos(2).locals["this"];
			if (!(className in fileScope))
				return;

			// actually run hooks
			this.__registerClass(_src, fileScope[className]);
		}
		catch (error)
		{
			::Hooks.error(" src: " + _src + " " + error);
		}
	}
}
