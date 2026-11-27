package cc.screenguard.mobile

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.Inet4Address

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "cc.screenguard.mobile/tailnet")
            .setMethodCallHandler { call, result ->
                if (call.method == "peers") result.success(tailnetPeers()) else result.notImplemented()
            }
    }

    /**
     * IPv4 addresses of the Tailscale peers this phone can reach.
     *
     * Tailscale's Android client routes every peer as its own /32 through its
     * VPN, and those routes are visible to other apps — the only peer list an
     * app outside Tailscale can read. A tailnet whose control plane switches on
     * Tailscale's single-CGNAT-route mode (one 100.64.0.0/10 route instead),
     * or a Tailscale split-tunnel setting that leaves this app out, yields no
     * peers. 100.64.0.0/10 is Tailscale's address space; 100.100.100.100 in it
     * is Tailscale's DNS resolver, not a peer.
     */
    @Suppress("DEPRECATION") // allNetworks: its replacement is a callback, overkill for a one-shot read
    private fun tailnetPeers(): List<String> {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val peers = linkedSetOf<String>()
        for (network in cm.allNetworks) {
            val caps = cm.getNetworkCapabilities(network) ?: continue
            if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
            val link = cm.getLinkProperties(network) ?: continue
            val own = link.linkAddresses.map { it.address }.toSet()
            for (route in link.routes) {
                val dest = route.destination
                val addr = dest.address
                if (dest.prefixLength != 32 || addr !is Inet4Address || addr in own) continue
                val b = addr.address
                if ((b[0].toInt() and 0xff) != 100 || (b[1].toInt() and 0xc0) != 64) continue
                val host = addr.hostAddress ?: continue
                if (host != "100.100.100.100") peers.add(host)
            }
        }
        return peers.toList()
    }
}
