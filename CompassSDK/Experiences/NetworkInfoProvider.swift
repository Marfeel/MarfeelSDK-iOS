import Foundation
import CoreTelephony

internal protocol NetworkInfoProviding {
    func getConnectionSpeedKbps() -> Int?
    func getConnectionType() -> String?
}

internal class NetworkInfoProvider: NetworkInfoProviding {
    func getConnectionSpeedKbps() -> Int? {
        // iOS doesn't expose downstream bandwidth like Android's ConnectivityManager.
        // Return nil; the server handles missing kbps gracefully.
        return nil
    }

    func getConnectionType() -> String? {
        if #available(iOS 12.0, *) {
            return getConnectionTypeViaPathMonitor()
        }
        return getConnectionTypeViaCellular()
    }

    @available(iOS 12.0, *)
    private func getConnectionTypeViaPathMonitor() -> String? {
        // NWPathMonitor is async; for a synchronous snapshot use the CTTelephonyNetworkInfo
        // combined with reachability check. Since we need a quick sync answer, fall back
        // to the cellular approach which is synchronous.
        return getConnectionTypeViaCellular()
    }

    private func getConnectionTypeViaCellular() -> String? {
        let info = CTTelephonyNetworkInfo()
        if let radio = info.currentRadioAccessTechnology {
            if radio.isEmpty { return nil }
            return "cellular"
        }
        // If no cellular, assume wifi (most common for simulator/devices with no SIM)
        return "wifi"
    }
}
