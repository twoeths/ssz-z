const std = @import("std");
const Scanner = std.json.Scanner;
const Allocator = std.mem.Allocator;
const AllocatorError = Allocator.Error;
const NextError = Scanner.NextError;
const FromHexError = @import("util").FromHexError;

pub const ScannerError = NextError;
pub const ParseUIntError = error{ InvalidNumber, Overflow, InvalidChacter } || std.fmt.ParseIntError || std.fmt.ParseFloatError || AllocatorError || ScannerError;
pub const JsonError = ParseUIntError || FromHexError || error{ InvalidJson, InCorrectLen };
pub const SszError = AllocatorError || error{ OutOfMemory, InCorrectLen } || error{ invalidFixedSize, zeroOffset, offsetNotDivisibleBy4, offsetOutOfRange, offsetNotIncreasing };
pub const HashError = error{ InCorrectLen, InvalidInput, noInitZeroHash, OutOfBounds, OutOfMemory };
