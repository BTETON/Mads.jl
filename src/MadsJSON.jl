import JSON
import DataStructures

"""
Load a JSON file

$(documentfunction(loadjsonfile))
"""
function loadjsonfile(filename::String) # load JSON text file
	sz = filesize(filename)
	f = open(filename, "r")
	a = Mmap.mmap(f, Vector{UInt8}, sz)
	s = convert(String, a) # ASCIIString is needed; urgh
	data = JSON.parse(s; dicttype=DataStructures.OrderedDict)
	finalize(a)
	close(f)
	return data
end

"""
Dump a JSON file

$(documentfunction(dumpjsonfile))
"""
function dumpjsonfile(filename::String, data) # dump JSON text file
	f = open(filename, "w")
	JSON.print(f, data)
	close(f)
end

"""
Read MADS model predictions from a JSON file

$(documentfunction(readjsonpredictions))
"""
function readjsonpredictions(filename::String) # read JSON text predictions
	return loadjsonfile(filename)
end
