if VERSION < v"0.4.0-dev"
	using Docile # default for v > 0.4
end

"Load JSON file"
function loadjsonfile(filename::AbstractString) # load JSON text file
	data = JSON.parsefile(filename; dicttype=DataStructures.OrderedDict, use_mmap=true)
	return data
end

"Dump JSON file"
function dumpjsonfile(filename::AbstractString, data) # dump JSON text file
	f = open(filename, "w")
	JSON.print(f, data)
	close(f)
end

"Read MADS predictions from a JSON file"
function readjsonpredictions(filename::AbstractString) # read JSON text predictions
	return loadjsonfile(filename)
end