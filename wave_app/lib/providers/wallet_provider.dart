import 'package:flutter/material.dart';
import 'package:reown_appkit/reown_appkit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart';

class WalletProvider extends ChangeNotifier {
  ReownAppKit? _appKit;
  String? _address;
  double _balance = 0.0;
  bool _isConnected = false;
  bool _isConnecting = false;
  String? _errorMessage;

  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get address => _address;
  double get balance => _balance;
  String? get errorMessage => _errorMessage;

  static const String _projectId = '82c1b93b-b0d0-4126-b705-11f22e62c1c0'; 

  Future<void> init() async {
    try {
      _appKit = await ReownAppKit.createInstance(
        projectId: _projectId,
        metadata: const PairingMetadata(
          name: 'wave.',
          description: 'wave. — Music Redefined',
          url: 'https://wave.app',
          icons: ['https://wave.app/logo.png'],
          redirect: Redirect(
            native: 'waveapp://',
            universal: 'https://wave.app',
          ),
        ),
      );

      // Listen for session events
      _appKit!.onSessionConnect.subscribe(_onSessionConnect);
      _appKit!.onSessionDelete.subscribe(_onSessionDelete);
      _appKit!.onSessionUpdate.subscribe(_onSessionUpdate);

      // In reown_appkit 1.5.0, sessions are managed via the web3App property
      // or similar getters if using the modal wrapper.
      // We try to access the underlying sessions.
    } catch (e) {
      debugPrint('[wave] AppKit init error: $e');
    }
  }

  String? _getAddressFromSession(SessionData session) {
    if (session.namespaces.containsKey('eip155')) {
      final accounts = session.namespaces['eip155']?.accounts;
      if (accounts != null && accounts.isNotEmpty) {
        return accounts[0].split(':').last;
      }
    }
    return null;
  }

  void _onSessionConnect(SessionConnect? args) {
    if (args != null) {
      _isConnected = true;
      _address = _getAddressFromSession(args.session);
      _isConnecting = false;
      notifyListeners();
      _fetchBalance();
    }
  }

  void _onSessionUpdate(SessionUpdate? args) {
    // SessionUpdate usually contains the topic
    // We can fetch the address from the provider or session if available
    notifyListeners();
  }

  void _onSessionDelete(SessionDelete? args) {
    _isConnected = false;
    _address = null;
    _balance = 0.0;
    notifyListeners();
  }

  Future<void> connect() async {
    if (_appKit == null) await init();

    _isConnecting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final ConnectResponse connectResponse = await _appKit!.connect(
        optionalNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:10143'], 
            methods: ['eth_sendTransaction', 'personal_sign', 'eth_signTypedData'],
            events: ['chainChanged', 'accountsChanged'],
          ),
        },
      );

      final Uri? uri = connectResponse.uri;
      if (uri != null) {
        final String metamaskUri = 'metamask://wc?uri=${Uri.encodeComponent(uri.toString())}';
        if (await canLaunchUrl(Uri.parse(metamaskUri))) {
          await launchUrl(Uri.parse(metamaskUri), mode: LaunchMode.externalApplication);
        } else {
          final String wcUri = 'wc:?uri=${Uri.encodeComponent(uri.toString())}';
          if (await canLaunchUrl(Uri.parse(wcUri))) {
            await launchUrl(Uri.parse(wcUri), mode: LaunchMode.externalApplication);
          } else {
            _errorMessage = 'MetaMask or compatible wallet not found.';
            _isConnecting = false;
            notifyListeners();
            return;
          }
        }
      }

      await connectResponse.session.future;
    } catch (e) {
      _isConnecting = false;
      _errorMessage = 'Failed to connect wallet: $e';
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    // Simplified disconnect for now to avoid topic errors
    _onSessionDelete(null);
  }

  Future<String?> sendBet(String trackId, bool isBanger) async {
    if (_appKit == null || !_isConnected) return null;

    try {
      // Use dynamic to access getActiveSessions while I'm on this 1.5.0 version
      // In production, ReownAppKit provides a web3App instance
      final dynamic sessions = (_appKit as dynamic).getActiveSessions();
      if (sessions.isEmpty) return null;
      final topic = sessions.values.first.topic;

      final String amountHex = '0x2386F26FC10000'; // 0.01 MON
      final String toAddress = '0x742d35Cc6634C0532925a3b844Bc454e4438f44e';

      final Map<String, dynamic> transaction = {
        'from': _address,
        'to': toAddress,
        'value': amountHex,
        'data': '0x',
      };

      final dynamic response = await (_appKit as dynamic).request(
        topic: topic,
        chainId: 'eip155:10143', 
        request: SessionRequestParams(
          method: 'eth_sendTransaction',
          params: [transaction],
        ),
      );

      _fetchBalance();
      return response.toString();
    } catch (e) {
      debugPrint('[wave] Bet Error: $e');
      _errorMessage = 'Transaction failed: $e';
      notifyListeners();
      return null;
    }
  }

  Future<void> _fetchBalance() async {
    if (_address == null) return;
    try {
      final client = Web3Client('https://testnet-rpc.monad.xyz', Client());
      final amount = await client.getBalance(EthereumAddress.fromHex(_address!));
      _balance = amount.getValueInUnit(EtherUnit.ether);
      notifyListeners();
      await client.dispose();
    } catch (e) {
      debugPrint('[wave] Balance fetch error: $e');
    }
  }
}
