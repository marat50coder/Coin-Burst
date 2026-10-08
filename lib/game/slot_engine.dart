import 'dart:math';

/// All symbols that can appear on reels. Base-game symbols come first,
/// bonus-game-only symbols (coin tiers, thunder, empty background) follow.
enum Symbol {
  // Base game fruit / bar / wild symbols.
  cherry,
  lemon,
  orange,
  watermelon,
  grape,
  bell,
  bar,
  wild, // the 777 symbol (scatter triggering the bonus)

  // Bonus-only symbols.
  coinMini,
  coinMinor,
  coinMajor,
  coinGrand,
  thunder,
  empty, // transparent cell inside the bonus reel strip
}

extension SymbolExt on Symbol {
  bool get isBaseSymbol {
    switch (this) {
      case Symbol.cherry:
      case Symbol.lemon:
      case Symbol.orange:
      case Symbol.watermelon:
      case Symbol.grape:
      case Symbol.bell:
      case Symbol.bar:
      case Symbol.wild:
        return true;
      default:
        return false;
    }
  }

  bool get isCoin {
    switch (this) {
      case Symbol.coinMini:
      case Symbol.coinMinor:
      case Symbol.coinMajor:
      case Symbol.coinGrand:
        return true;
      default:
        return false;
    }
  }

  /// Payout value in units of TOTAL spin bet. Only defined for coin tiers.
  /// Values are tuned so the combined (base + bonus) RTP sits near 98%
  /// *with* the "max 1 bonus symbol per reel" rule in effect.
  double get coinMultiplier {
    switch (this) {
      case Symbol.coinMini:
        return 5;
      case Symbol.coinMinor:
        return 17;
      case Symbol.coinMajor:
        return 55;
      case Symbol.coinGrand:
        return 350;
      default:
        return 0;
    }
  }

  /// Human-readable tier label (shown overlaid on the coin asset).
  String get coinTierLabel {
    switch (this) {
      case Symbol.coinMini:
        return 'MINI';
      case Symbol.coinMinor:
        return 'MINOR';
      case Symbol.coinMajor:
        return 'MAJOR';
      case Symbol.coinGrand:
        return 'GRAND';
      default:
        return '';
    }
  }

  /// Asset path for this symbol. `null` for [Symbol.empty] (no artwork).
  String? get asset {
    switch (this) {
      case Symbol.cherry:
        return 'assets/Coin_Burst_gameplay_assets/cherry_asset.webp';
      case Symbol.lemon:
        return 'assets/Coin_Burst_gameplay_assets/lemon_asset.webp';
      case Symbol.orange:
        return 'assets/Coin_Burst_gameplay_assets/apple_asset.webp';
      case Symbol.watermelon:
        return 'assets/Coin_Burst_gameplay_assets/watermelon_asset.webp';
      case Symbol.grape:
        return 'assets/Coin_Burst_gameplay_assets/grape_asset.webp';
      case Symbol.bell:
        return 'assets/Coin_Burst_gameplay_assets/bell_asset.webp';
      case Symbol.bar:
        return 'assets/Coin_Burst_gameplay_assets/bar_asset.webp';
      case Symbol.wild:
        return 'assets/Coin_Burst_gameplay_assets/7_wild_asset.webp';
      case Symbol.coinMini:
        return 'assets/Coin_Burst_gameplay_assets/mini_bonus_asset.webp';
      case Symbol.coinMinor:
        return 'assets/Coin_Burst_gameplay_assets/minor_bonus_asset.webp';
      case Symbol.coinMajor:
        return 'assets/Coin_Burst_gameplay_assets/major_bonus_asset.webp';
      case Symbol.coinGrand:
        return 'assets/Coin_Burst_gameplay_assets/grand_bonus_asset.webp';
      case Symbol.thunder:
        return 'assets/Coin_Burst_gameplay_assets/thunder_asset.webp';
      case Symbol.empty:
        return null;
    }
  }
}

/// Base-game reel strip symbols (what we show when scrolling base reels).
const List<Symbol> baseStripPool = <Symbol>[
  Symbol.cherry,
  Symbol.lemon,
  Symbol.orange,
  Symbol.watermelon,
  Symbol.grape,
  Symbol.bell,
  Symbol.bar,
  Symbol.wild,
];

/// Bonus-game reel strip symbols. Must match the roll weights conceptually.
const List<Symbol> bonusStripPool = <Symbol>[
  Symbol.empty,
  Symbol.empty,
  Symbol.empty,
  Symbol.empty,
  Symbol.coinMini,
  Symbol.coinMini,
  Symbol.coinMinor,
  Symbol.coinMajor,
  Symbol.coinGrand,
  Symbol.thunder,
];

/// When `true`, boosts bonus-trigger probability and high-paying symbols for
/// easier manual testing. Set to `false` before shipping.
const bool kDebugEasyWins = true;

/// Base-game reel weights (used for drawing final symbols on each cell).
const Map<Symbol, int> _reelWeightsProd = <Symbol, int>{
  Symbol.cherry: 22,
  Symbol.lemon: 20,
  Symbol.orange: 18,
  Symbol.watermelon: 14,
  Symbol.grape: 10,
  Symbol.bell: 7,
  Symbol.bar: 4,
  Symbol.wild: 5,
};

/// Debug variant: significantly boosts high-tier symbols + wilds so bonus
/// triggers and good combinations are frequent during QA.
const Map<Symbol, int> _reelWeightsDebug = <Symbol, int>{
  Symbol.cherry: 10,
  Symbol.lemon: 10,
  Symbol.orange: 10,
  Symbol.watermelon: 10,
  Symbol.grape: 12,
  Symbol.bell: 14,
  Symbol.bar: 14,
  Symbol.wild: 20,
};

Map<Symbol, int> get _reelWeights =>
    kDebugEasyWins ? _reelWeightsDebug : _reelWeightsProd;

/// Bonus-cell weights — debug variant lands coins more often.
const Map<Symbol, int> _bonusCellWeightsProd = <Symbol, int>{
  Symbol.empty: 700,
  Symbol.coinMini: 170,
  Symbol.coinMinor: 60,
  Symbol.coinMajor: 15,
  Symbol.coinGrand: 3,
  Symbol.thunder: 52,
};

const Map<Symbol, int> _bonusCellWeightsDebug = <Symbol, int>{
  Symbol.empty: 250,
  Symbol.coinMini: 220,
  Symbol.coinMinor: 160,
  Symbol.coinMajor: 90,
  Symbol.coinGrand: 25,
  Symbol.thunder: 110,
};

Map<Symbol, int> get _bonusCellWeightsActive =>
    kDebugEasyWins ? _bonusCellWeightsDebug : _bonusCellWeightsProd;

/// 3-of-a-kind payout (multiplier of per-line bet). We bet across 5 lines, so
/// the "total bet" is 5 x line bet. Values rebalanced upward to compensate
/// for the "max 1 wild per reel" + "max 1 bonus coin per reel" rules that
/// cut effective bonus throughput.
const Map<Symbol, double> _threeOfAKindPayoutPerLine = <Symbol, double>{
  Symbol.cherry: 14,
  Symbol.lemon: 20,
  Symbol.orange: 30,
  Symbol.watermelon: 48,
  Symbol.grape: 85,
  Symbol.bell: 170,
  Symbol.bar: 430,
  Symbol.wild: 850,
};

class LinePayout {
  final int lineIndex;
  final Symbol symbol;
  final int count; // 3 only in current rules
  final double multiplier; // per-line bet multiplier
  final List<List<int>> positions; // list of [row,col]

  const LinePayout({
    required this.lineIndex,
    required this.symbol,
    required this.count,
    required this.multiplier,
    required this.positions,
  });
}

class SpinResult {
  /// 3 columns, 3 rows. grid[col][row] = symbol.
  final List<List<Symbol>> grid;
  final List<LinePayout> wins;
  final double winMultiplierOfTotalBet;
  final bool triggersBonus;
  final List<List<int>> wildScatterPositions;

  const SpinResult({
    required this.grid,
    required this.wins,
    required this.winMultiplierOfTotalBet,
    required this.triggersBonus,
    required this.wildScatterPositions,
  });
}

/// Result of a single bonus spin. Independent of previous spins — no hold.
class BonusSpinResult {
  /// 3x3 final grid [col][row]. Cells can be empty, coinXxx or thunder.
  final List<List<Symbol>> grid;

  /// Positions where a coin landed this spin.
  final List<List<int>> coinPositions; // [row,col]

  /// Positions where the thunder symbol landed.
  final List<List<int>> thunderPositions;

  /// Whether thunder appeared on this spin → triggers collection.
  final bool thunder;

  /// Amount credited to the player (in bet multiples). Non-zero only when
  /// thunder landed; it then sums every coin on the current grid.
  final double collectedMultiplier;

  const BonusSpinResult({
    required this.grid,
    required this.coinPositions,
    required this.thunderPositions,
    required this.thunder,
    required this.collectedMultiplier,
  });
}

class SlotEngine {
  final Random _rng = Random();

  // 5 paylines on a 3x3 grid.
  static const List<List<int>> paylines = <List<int>>[
    <int>[0, 0, 0],
    <int>[1, 1, 1],
    <int>[2, 2, 2],
    <int>[0, 1, 2],
    <int>[2, 1, 0],
  ];

  static const int numLines = 5;

  Symbol _randomBaseSymbol() {
    final int total = _reelWeights.values.fold<int>(0, (sum, w) => sum + w);
    int roll = _rng.nextInt(total);
    for (final MapEntry<Symbol, int> entry in _reelWeights.entries) {
      roll -= entry.value;
      if (roll < 0) return entry.key;
    }
    return Symbol.cherry;
  }

  Symbol _randomBonusCell() {
    final Map<Symbol, int> weights = _bonusCellWeightsActive;
    final int total = weights.values.fold<int>(0, (sum, w) => sum + w);
    int roll = _rng.nextInt(total);
    for (final MapEntry<Symbol, int> entry in weights.entries) {
      roll -= entry.value;
      if (roll < 0) return entry.key;
    }
    return Symbol.empty;
  }

  SpinResult spin({required double totalBet}) {
    // Build the grid column-by-column so we can enforce "max 1 wild per
    // reel". A reel == one column (top → bottom). If the first non-wild
    // roll already placed a wild, every subsequent wild roll in the same
    // column is substituted for a weighted non-wild symbol.
    final List<List<Symbol>> grid = List<List<Symbol>>.generate(
      3,
      (_) => List<Symbol>.filled(3, Symbol.cherry),
    );
    for (int col = 0; col < 3; col++) {
      bool wildPlaced = false;
      for (int row = 0; row < 3; row++) {
        Symbol s = _randomBaseSymbol();
        if (s == Symbol.wild) {
          if (wildPlaced) {
            // Re-roll until a non-wild lands so we don't bias the symbol
            // distribution with a hard substitution.
            while (s == Symbol.wild) {
              s = _randomBaseSymbol();
            }
          } else {
            wildPlaced = true;
          }
        }
        grid[col][row] = s;
      }
    }

    final double perLineBet = totalBet / numLines;
    final List<LinePayout> wins = <LinePayout>[];
    double totalWin = 0;

    for (int i = 0; i < paylines.length; i++) {
      final List<int> line = paylines[i];
      final Symbol s0 = grid[0][line[0]];
      final Symbol s1 = grid[1][line[1]];
      final Symbol s2 = grid[2][line[2]];
      if (s0 == s1 && s1 == s2) {
        final double m = _threeOfAKindPayoutPerLine[s0] ?? 0;
        if (m > 0) {
          final double win = m * perLineBet;
          totalWin += win;
          wins.add(LinePayout(
            lineIndex: i,
            symbol: s0,
            count: 3,
            multiplier: m,
            positions: <List<int>>[
              <int>[line[0], 0],
              <int>[line[1], 1],
              <int>[line[2], 2],
            ],
          ));
        }
      }
    }

    final List<List<int>> wildPositions = <List<int>>[];
    for (int col = 0; col < 3; col++) {
      for (int row = 0; row < 3; row++) {
        if (grid[col][row] == Symbol.wild) {
          wildPositions.add(<int>[row, col]);
        }
      }
    }
    // Bonus triggers on exactly 3 wild scatters. Combined with the
    // "max 1 wild per reel" constraint above, that means ALL three reels
    // need to roll a wild — maximum tension, matches player expectations.
    final bool triggersBonus = wildPositions.length >= 3;

    final double winMultiplier =
        totalBet == 0 ? 0 : (totalWin / totalBet);

    return SpinResult(
      grid: grid,
      wins: wins,
      winMultiplierOfTotalBet: winMultiplier,
      triggersBonus: triggersBonus,
      wildScatterPositions: wildPositions,
    );
  }

  // ---- Bonus game (independent spins + thunder trigger) ----

  /// Spin bonus reels. Every spin is fully independent — coins do NOT carry
  /// between spins. A spin only pays out when the thunder symbol is on the
  /// grid, in which case every coin on the same grid is credited.
  ///
  /// Reel constraint: at most one non-empty symbol (coin or thunder) per
  /// column (top → bottom). "Reel" == column.
  BonusSpinResult bonusSpin() {
    final List<List<Symbol>> grid = List<List<Symbol>>.generate(
      3,
      (_) => List<Symbol>.filled(3, Symbol.empty),
    );
    final List<List<int>> coinPositions = <List<int>>[];
    final List<List<int>> thunderPositions = <List<int>>[];

    for (int col = 0; col < 3; col++) {
      final List<int> rows = <int>[0, 1, 2]..shuffle(_rng);
      bool nonEmptyPlaced = false;
      for (final int row in rows) {
        Symbol s = _randomBonusCell();
        if (s != Symbol.empty && nonEmptyPlaced) {
          s = Symbol.empty;
        }
        grid[col][row] = s;
        if (s != Symbol.empty) {
          nonEmptyPlaced = true;
          if (s.isCoin) {
            coinPositions.add(<int>[row, col]);
          } else if (s == Symbol.thunder) {
            thunderPositions.add(<int>[row, col]);
          }
        }
      }
    }

    final bool thunder = thunderPositions.isNotEmpty;
    double collected = 0;
    if (thunder) {
      for (final List<int> p in coinPositions) {
        collected += grid[p[1]][p[0]].coinMultiplier;
      }
    }

    return BonusSpinResult(
      grid: grid,
      coinPositions: coinPositions,
      thunderPositions: thunderPositions,
      thunder: thunder,
      collectedMultiplier: collected,
    );
  }
}
