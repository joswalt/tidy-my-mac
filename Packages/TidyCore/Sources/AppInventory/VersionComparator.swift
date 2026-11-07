import Foundation

// A Swift port of Sparkle's SUStandardVersionComparator (spec 013 §4), kept line-for-line in
// behaviour, including its known `.1` quirk. Ported from sparkle-project/Sparkle, branch 2.x at
// commit 14fdbf28dc7c6fd8741a144bff517ef86572e6c2, Sparkle/SUStandardVersionComparator.m.
//
// Copyright (c) 2006-2013 Andy Matuschak. Copyright (c) 2009-2013 Elgato Systems GmbH.
// Copyright (c) 2011-2014 Kornel Lesiński. Copyright (c) 2015-2017 Mayur Pawashe.
// Copyright (c) 2014 C.W. Betts. Copyright (c) 2014 Petroules Corporation.
// Copyright (c) 2014 Big Nerd Ranch. MIT licence; full text in ThirdPartyLicenses/Sparkle.txt.

public enum VersionComparator {
    enum CharacterType { case number, string, periodSeparator, punctuationSeparator, whitespaceSeparator, dash }

    static func type(of part: String) -> CharacterType {
        guard let scalar = part.unicodeScalars.first else { return .string }
        if part.hasPrefix(".") { return .periodSeparator }
        if part.hasPrefix("-") { return .dash }
        if CharacterSet.decimalDigits.contains(scalar) { return .number }
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return .whitespaceSeparator }
        if CharacterSet.punctuationCharacters.contains(scalar) { return .punctuationSeparator }
        return .string
    }

    static func isSeparator(_ t: CharacterType) -> Bool {
        switch t {
        case .number, .string, .dash: false
        case .periodSeparator, .punctuationSeparator, .whitespaceSeparator: true
        }
    }

    /// Separators of any kind count as the same class.
    static func sameClass(_ a: CharacterType, _ b: CharacterType) -> Bool {
        isSeparator(a) ? isSeparator(b) : a == b
    }

    /// Splits into runs of one character type; each separator is its own part; stops at `-`.
    static func split(_ version: String) -> [String] {
        // Sparkle walks UTF-16 code units; versions are ASCII in practice, scalars match it there.
        let scalars = Array(version.unicodeScalars)
        guard let first = scalars.first else { return [] }
        var parts: [String] = []
        var s = String(first)
        var oldType = type(of: s)
        for scalar in scalars.dropFirst() {
            let c = String(scalar)
            let newType = type(of: c)
            if newType == .dash { break }
            if oldType != newType || isSeparator(oldType) {
                parts.append(s)
                s = c
            } else {
                s += c
            }
            oldType = newType
        }
        parts.append(s)
        return parts
    }

    static func countOfNumberAndPeriodStartingParts(_ parts: [String]) -> Int {
        var count = 0
        for p in parts {
            let t = type(of: p)
            guard t == .number || t == .periodSeparator else { break }
            count += 1
        }
        return count
    }

    /// Pads the shorter leading number/period run so `1.0` equals `1.0.0`.
    static func balance(_ a: inout [String], _ b: inout [String]) {
        let ca = countOfNumberAndPeriodStartingParts(a), cb = countOfNumberAndPeriodStartingParts(b)
        func pad(_ to: inout [String], _ toCount: Int, from: [String], _ fromCount: Int) {
            for i in toCount..<fromCount {
                to.insert(type(of: from[i]) == .periodSeparator ? "." : "0", at: i)
            }
        }
        if ca > cb { pad(&b, cb, from: a, ca) } else if cb > ca { pad(&a, ca, from: b, cb) }
    }

    public static func compare(_ versionA: String, _ versionB: String) -> ComparisonResult {
        var partsA = split(versionA), partsB = split(versionB)
        balance(&partsA, &partsB)
        let n = min(partsA.count, partsB.count)
        for i in 0..<n {
            let a = partsA[i], b = partsB[i]
            let ta = type(of: a), tb = type(of: b)
            if sameClass(ta, tb) {
                if ta == .number {
                    let va = Int64(a) ?? Int64.max, vb = Int64(b) ?? Int64.max
                    if va > vb { return .orderedDescending }
                    if va < vb { return .orderedAscending }
                } else if ta == .string {
                    let r = (a as NSString).compare(b)
                    if r != .orderedSame { return r }
                }
            } else {
                if ta != .string && tb == .string { return .orderedDescending }
                if ta == .string && tb != .string { return .orderedAscending }
                // One is a number and the other a period: the period is invalid.
                return ta == .number ? .orderedDescending : .orderedAscending
            }
        }
        if partsA.count != partsB.count {
            let (missing, shorter, larger): (String, ComparisonResult, ComparisonResult) = partsA.count > partsB.count
                ? (partsA[n], .orderedAscending, .orderedDescending)
                : (partsB[n], .orderedDescending, .orderedAscending)
            return type(of: missing) == .string ? shorter : larger
        }
        return .orderedSame
    }

    /// True when `available` is newer than `installed` (an update exists only on `.orderedDescending`).
    public static func isNewer(_ available: String, than installed: String) -> Bool {
        compare(available, installed) == .orderedDescending
    }
}
