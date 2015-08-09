using Distributions
using DataStructures
import R3Function
if VERSION < v"0.4.0-dev"
	using Docile # default for v > 0.4
end

@doc "Set MADS input file" ->
function setmadsinputfile(filename)
	global madsinputfile = filename
end

@doc "Get MADS input file" ->
function getmadsinputfile()
	return madsinputfile
end

@doc "Make MADS command function" ->
function madsrootname(madsdata)
	join(split(madsdata["Filename"], ".")[1:end-1], ".")
end

@doc "Make MADS command function" ->
function makemadscommandfunction(madsdata) # make MADS command function
	if haskey(madsdata, "Dynamic model") # TODO do we still need "Dynamic model"?
		println("Dynamic model evaluation ...")
		madscommandfunction = madsdata["Dynamic model"]
	elseif haskey(madsdata, "Model")
		println("Internal model evaluation ...")
		madscommandfunction = evalfile(joinpath(pwd(), madsdata["Model"]))
	elseif haskey(madsdata, "Command")
		madsinfo("External command execution ...")
		function madscommandfunction(parameters::Dict) # MADS command function
			newdirname = "../$(split(pwd(),"/")[end])_$(strftime("%Y%m%d%H%M",time()))_$(randstring(6))_$(myid())"
			madsinfo("""Temp directory: $(newdirname)""")
			run(`mkdir $newdirname`)
			currentdir = pwd()
			run(`bash -c "ln -s $(currentdir)/* $newdirname"`) # link all the files in the current directory
			if haskey(madsdata, "Instructions") # Templates/Instructions
				for instruction in madsdata["Instructions"]
					filename = instruction["read"]
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
			end
			if haskey(madsdata, "Templates") # Templates/Instructions
				for template in madsdata["Templates"]
					filename = template["write"]
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
				cd(newdirname)
				writeparameters(madsdata, parameters)
				cd(currentdir)
			end
			#TODO move the writing into the "writeparameters" function
			if haskey(madsdata, "JSONParameters") # JSON
				for filename in vcat(madsdata["JSONParameters"]) # the vcat is needed in case madsdata["..."] contains only one thing
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
				dumpjsonfile("$(newdirname)/$(madsdata["JSONParameters"])", parameters) # create parameter files
			end
			if haskey(madsdata, "JSONPredictions") # JSON
				for filename in vcat(madsdata["JSONPredictions"]) # the vcat is needed in case madsdata["..."] contains only one thing
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
			end
			if haskey(madsdata, "YAMLParameters") # YAML
				for filename in vcat(madsdata["YAMLParameters"]) # the vcat is needed in case madsdata["..."] contains only one thing
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
				dumpyamlfile("$(newdirname)/$(madsdata["YAMLParameters"])", parameters) # create parameter files
			end
			if haskey(madsdata, "YAMLPredictions") # YAML
				for filename in vcat(madsdata["YAMLPredictions"]) # the vcat is needed in case madsdata["..."] contains only one thing
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
			end
			if haskey(madsdata, "ASCIIParameters") # ASCII
				for filename in vcat(madsdata["ASCIIParameters"]) # the vcat is needed in case madsdata["..."] contains only one thing
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
				dumpasciifile("$(newdirname)/$(madsdata["ASCIIParameters"])", values(parameters)) # create parameter files
			end
			if haskey(madsdata, "ASCIIPredictions") # ASCII
				for filename in vcat(madsdata["ASCIIPredictions"]) # the vcat is needed in case madsdata["..."] contains only one thing
					run(`rm -f $(newdirname)/$filename`) # delete the parameter file links
				end
			end
			if haskey(madsdata, "JuliaModel")
				println("Internal Julia model evaluation ...")
				madscommandfunction = evalfile(madsdata["JuliaModel"])
				results = madscommandfunction(parameters)
			else
				madsinfo("""Execute: $(madsdata["Command"])""")
				run(`bash -c "cd $newdirname; $(madsdata["Command"])"`)
				results = DataStructures.OrderedDict()
				if haskey(madsdata, "Instructions") # Templates/Instructions
					cd(newdirname)
					results = readobservations(madsdata)
					cd(currentdir)
					madsinfo("""Observations: $(results)""")
				elseif haskey(madsdata, "JSONPredictions") # JSON
					for filename in vcat(madsdata["JSONPredictions"]) # the vcat is needed in case madsdata["..."] contains only one thing
						results = loadjsonfile("$(newdirname)/$filename")
					end
				elseif haskey(madsdata, "YAMLPredictions") # YAML
					for filename in vcat(madsdata["YAMLPredictions"]) # the vcat is needed in case madsdata["..."] contains only one thing
						results = merge(results, loadyamlfile("$(newdirname)/$filename"))
					end
				elseif haskey(madsdata, "ASCIIPredictions") # ASCII
					predictions = loadasciifile("$(newdirname)/$(madsdata["ASCIIPredictions"])")
					obskeys = getobskeys(madsdata)
					obsid=[convert(String,k) for k in obskeys]
					@assert length(obskeys) == length(predictions)
					results = DataStructures.OrderedDict{String, Float64}(zip(obsid, predictions))
				end
				run(`rm -fR $newdirname`)
				return results
			end
		end
	elseif haskey(madsdata, "Sources") # we may still use "Wells" instead of "Observations"
		return makecomputeconcentrations(madsdata)
	else
		error("Cannot create a madscommand function without a Model or a Command entry in the mads input file")
	end
	if !haskey(madsdata, "Restart") || madsdata["Restart"] != false
		rootname = join(split(split(madsdata["Filename"], "/")[end], ".")[1:end-1], ".")
		if haskey(madsdata, "RestartDir")
			rootdir = madsdata["RestartDir"]
		elseif contains(madsdata["Filename"], "/")
			rootdir = string(join(split(madsdata["Filename"], "/")[1:end-1], "/"), "/", rootname, "_restart")
		else
			rootdir = string(rootname, "_restart")
		end
		madscommandfunctionwithreuse = R3Function.maker3function(madscommandfunction, rootdir)
		return madscommandfunctionwithreuse
	else
		return madscommandfunction
	end
end

@doc "Make MADS command gradient function" ->
function makemadscommandgradient(madsdata) # make MADS command gradient function
	f = makemadscommandfunction(madsdata)
	return makemadscommandgradient(madsdata, f)
end

@doc "Make MADS command gradient function" ->
function makemadscommandgradient(madsdata, f::Function) # make MADS command gradient function
	optparamkeys = getoptparamkeys(madsdata)
	function madscommandgradient(parameters::Dict) # MADS command gradient function
		xph = Dict()
		h = sqrt(eps(Float32))
		xph["noparametersvaried"] = parameters
		i = 2
		for optparamkey in optparamkeys
			xph[optparamkey] = copy(parameters)
			xph[optparamkey][optparamkey] += h
			i += 1
		end
		fevals = pmap(keyval->[keyval[1], f(keyval[2])], xph)
		fevalsdict = Dict()
		for feval in fevals
			fevalsdict[feval[1]] = feval[2]
		end
		gradient = Dict()
		resultkeys = keys(fevals[1][2])
		for resultkey in resultkeys
			gradient[resultkey] = Dict()
			for optparamkey in optparamkeys
				gradient[resultkey][optparamkey] = (fevalsdict[optparamkey][resultkey] - fevalsdict["noparametersvaried"][resultkey]) / h
			end
		end
		return gradient
	end
	return madscommandgradient
end

@doc "Make MADS command function & gradient function" ->
function makemadscommandfunctionandgradient(madsdata)
	f = makemadscommandfunction(madsdata)
	optparamkeys = getoptparamkeys(madsdata)
	function madscommandfunctionandgradient(parameters::Dict) # MADS command gradient function
		xph = Dict()
		h = sqrt(eps(Float32))
		xph["noparametersvaried"] = parameters
		i = 2
		for optparamkey in optparamkeys
			xph[optparamkey] = copy(parameters)
			xph[optparamkey][optparamkey] += h
			i += 1
		end
		fevals = pmap(keyval->[keyval[1], f(keyval[2])], xph)
		fevalsdict = Dict()
		for feval in fevals
			fevalsdict[feval[1]] = feval[2]
		end
		gradient = Dict()
		resultkeys = keys(fevals[1][2])
		for resultkey in resultkeys
			gradient[resultkey] = Dict()
			for optparamkey in optparamkeys
				gradient[resultkey][optparamkey] = (fevalsdict[optparamkey][resultkey] - fevalsdict["noparametersvaried"][resultkey]) / h
			end
		end
		return fevalsdict["noparametersvaried"], gradient
	end
	return madscommandfunctionandgradient
end

@doc "Make MADS loglikelihood function" ->
function makemadsloglikelihood(madsdata)
	if haskey(madsdata, "LogLikelihood")
		madsinfo("Internal log likelihood")
		madsloglikelihood = evalfile(madsdata["LogLikelihood"]) # madsloglikelihood should be a function that takes a dict of MADS parameters, a dict of model predictions, and a dict of MADS observations
	else
		madsinfo("External log likelihood")
		function madsloglikelihood{T1<:Associative, T2<:Associative, T3<:Associative}(params::T1, predictions::T2, observations::T3)
			#TODO replace this sum of squared residuals approach with the distribution from the "dist" observation keyword if it is there
			wssr = 0.
			for paramname in keys(params)
				if params[paramname] < madsdata["Parameters"][paramname]["min"] || params[paramname] > madsdata["Parameters"][paramname]["max"]
					return -Inf
				end
			end
			for obsname in keys(predictions)
				pred = predictions[obsname]
				obs = observations[obsname]["target"]
				weight = observations[obsname]["weight"]
				diff = obs - pred
				wssr += weight * diff * diff
			end
			return -wssr
		end
	end
	return madsloglikelihood
end

@doc "Get keys for parameters" ->
function getparamkeys(madsdata)
	return collect(keys(madsdata["Parameters"]))
	#return [convert(String,k) for k in keys(madsdata["Parameters"])]
end

@doc "Get keys for source parameters" ->
function getsourcekeys(madsdata)
	return collect(keys(madsdata["Sources"][1]["box"]))
	#return [convert(String,k) for k in keys(madsdata["Parameters"])]
end

@doc "Get keys for observations" ->
function getobskeys(madsdata)
	return collect(keys(madsdata["Observations"]))
	#return [convert(String,k) for k in keys(madsdata["Observations"])]
end

@doc "Get keys for wells" ->
function getwellkeys(madsdata)
	return collect(keys(madsdata["Wells"]))
	#return [convert(String,k) for k in keys(madsdata["Wells"])]
end

@doc "Write parameters via MADS template" ->
function writeparametersviatemplate(parameters, templatefilename, outputfilename)
	tplfile = open(templatefilename) # open template file
	line = readline(tplfile) # read the first line that says "template $separator\n"
	if length(line) == length("template #\n") && line[1:9] == "template "
		separator = line[end-1] # template separator
		lines = readlines(tplfile)
	else
		#it doesn't specify the separator -- assume it is '#'
		separator = '#'
		lines = [line; readlines(tplfile)]
	end
	close(tplfile)
	outfile = open(outputfilename, "w")
	for line in lines
		splitline = split(line, separator) # two separators are needed for each parameter
		@assert rem(length(splitline), 2) == 1 # length(splitlines) should always be an odd number -- if it isn't the assumptions in the code below fail
		for i = 1:int((length(splitline)-1)/2)
			write(outfile, splitline[2 * i - 1]) # write the text before the parameter separator
			madsinfo( "Replacing "*strip(splitline[2 * i])*" -> "*string(parameters[strip(splitline[2 * i])]) )
			write(outfile, string(parameters[strip(splitline[2 * i])])) # splitline[2 * i] in this case is parameter ID
		end
		write(outfile, splitline[end]) # write the rest of the line after the last separator
	end
	close(outfile)
end

@doc "Write initial parameters" ->
function writeparameters(madsdata)
	paramsinit = getparamsinit(madsdata)
	paramkeys = getparamkeys(madsdata)
	writeparameters(madsdata, Dict(paramkeys, paramsinit))
end

@doc "Write parameters" ->
function writeparameters(madsdata, parameters)
	expressions = evaluatemadsexpressions(parameters, madsdata)
	paramsandexps = merge(parameters, expressions)
	for template in madsdata["Templates"]
		writeparametersviatemplate(paramsandexps, template["tpl"], template["write"])
	end
end


@doc "Call C MADS ins_obs() function from the MADS library" ->
function cmadsins_obs(obsid::Array{Any,1}, instructionfilename::ASCIIString, inputfilename::ASCIIString)
	n = length(obsid)
	obsval = zeros(n) # initialize to 0
	obscheck = -1 * ones(n) # initialize to -1
	debug = 0 # setting debug level 0 or 1 works
	# int ins_obs( int nobs, char **obs_id, double *obs, double *check, char *fn_in_t, char *fn_in_d, int debug );
	result = ccall( (:ins_obs, "libmads"), Int32,
					(Int32, Ptr{Ptr{Uint8}}, Ptr{Float64}, Ptr{Float64}, Ptr{Uint8}, Ptr{Uint8}, Int32),
					n, obsid, obsval, obscheck, instructionfilename, inputfilename, debug)
	observations = Dict{String, Float64}(obsid, obsval)
	return observations
end

@doc "Read observations" ->
function readobservations(madsdata)
	obsids=getobskeys(madsdata)
	observations = Dict(obsids, zeros(length(obsids)))
	for instruction in madsdata["Instructions"]
		obs = cmadsins_obs(obsids, instruction["ins"], instruction["read"])
		#this loop assumes that cmadsins_obs gives a zero value if the obs is not found, and that each obs will appear only once
		for obsid in obsids
			observations[obsid] += obs[obsid]
		end
	end
	return observations
end

@doc "Get distributions" ->
function getdistributions(madsdata)
	paramkeys = getparamkeys(madsdata)
	distributions = Dict()
	for i in 1:length(paramkeys)
		if haskey(madsdata["Parameters"][paramkeys[i]], "dist")
			distributions[paramkeys[i]] = eval(parse(madsdata["Parameters"][paramkeys[i]]["dist"]))
		else
			distributions[paramkeys[i]] = Uniform(madsdata["Parameters"][paramkeys[i]]["min"], madsdata["Parameters"][paramkeys[i]]["max"])
		end
	end
	return distributions
end
