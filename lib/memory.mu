malloc(size usize) pointer #Foreign("malloc")
realloc(ptr pointer, new_size usize) pointer #Foreign("realloc")

Memory {
	newArenaAllocator(capacity ssize) {
		prev := ::currentAllocator
		::currentAllocator = heapAllocator()
		a := new ArenaAllocator(capacity)
		::currentAllocator = prev
		return a.iAllocator_escaping()
	}
	
	heapAllocator() {
		return IAllocator {
			allocFn: heapAllocFn,
			reallocFn: heapReallocFn,
		}
	}
	
	heapAllocFn(data pointer, numBytes ssize) {
		result := malloc(checked_cast(numBytes, usize))
		assert(result != null)
		return result
	}

	heapReallocFn(data pointer, ptr pointer, newSizeInBytes ssize, prevSizeInBytes ssize, copySizeInBytes ssize) {
		result := realloc(ptr, checked_cast(newSizeInBytes, usize))
		assert(result != null)
		return result
	}
}

ArenaAllocator struct #RefType {
	from pointer
	to pointer
	current pointer
	
	cons(capacity ssize) {
		from := ::currentAllocator.alloc(capacity)
		assert((transmute(from, usize) & 7) == 0) // Ensure qword aligned
		return ArenaAllocator { 
			from: from,
			current: from,
			to: from + capacity,
		}	
	}
	
	alloc(a ArenaAllocator, numBytes ssize) {
		runway := a.to.subtractSigned(a.current)
		assert(cast(numBytes, usize) <= cast(runway, usize))
		numBytes = (numBytes + 7) & ~7 // Round up to next qword
		ptr := a.current
		a.current += numBytes
		return ptr
	}
	
	realloc(a ArenaAllocator, ptr pointer, newSizeInBytes ssize, prevSizeInBytes ssize, copySizeInBytes ssize) {
		assert(cast(prevSizeInBytes, usize) <= cast(ssize.maxValue - 7, usize))
		prevSizeInBytes = (prevSizeInBytes + 7) & ~7
		if ptr + prevSizeInBytes == a.current && prevSizeInBytes > 0 {
			if newSizeInBytes > prevSizeInBytes {
				alloc(a, newSizeInBytes - prevSizeInBytes)
			} else {
				assert(newSizeInBytes >= 0)
				newSizeInBytes = (newSizeInBytes + 7) & ~7
				a.current = ptr + newSizeInBytes
			}			
			return ptr
		}	
		newPtr := a.alloc(newSizeInBytes)
		memcpy(newPtr, ptr, checked_cast(min(copySizeInBytes, newSizeInBytes), usize))
		return newPtr
	}
	
	iAllocator_escaping(a ArenaAllocator) {
		return IAllocator {
			data: pointer_cast(a, pointer),
			allocFn: pointer_cast(ArenaAllocator.alloc, fun<pointer, ssize, pointer>),
			reallocFn: pointer_cast(ArenaAllocator.realloc, fun<pointer, pointer, ssize, ssize, ssize, pointer>),
		}
	}
}
