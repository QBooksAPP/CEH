import 'package:flutter/material.dart';

import '../core/accounts_formatters.dart';
import '../core/ceh_theme.dart';

String formatNaira(num value) => formatNgn(value);

class AccountsSectionTitle extends StatelessWidget {
  const AccountsSectionTitle(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: Colors.black54)),
        ]),
      );
}

class AccountsSummaryCard extends StatelessWidget {
  const AccountsSummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.detail,
    this.icon = Icons.account_balance_wallet_outlined,
    this.emphasized = false,
  });
  final String label;
  final double value;
  final String detail;
  final IconData icon;
  final bool emphasized;

  @override
  Widget build(BuildContext context) => Card(
        color: emphasized ? CehTheme.navy : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon,
                color: emphasized ? Colors.white : CehTheme.blue, size: 30),
            const Spacer(),
            Text(label,
                style: TextStyle(
                    color: emphasized ? Colors.white70 : Colors.black54,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatNaira(value),
                  style: TextStyle(
                      color: emphasized ? Colors.white : CehTheme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w900)),
            ),
            const SizedBox(height: 5),
            Text(detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: emphasized ? Colors.white70 : Colors.black54,
                    fontSize: 12)),
          ]),
        ),
      );
}

class AccountsResponsiveGrid extends StatelessWidget {
  const AccountsResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 4,
    this.childAspectRatio = 1.6,
  });
  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final columns = box.maxWidth >= 1100
            ? desktopColumns
            : box.maxWidth >= 650
                ? tabletColumns
                : mobileColumns;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: childAspectRatio,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: children,
        );
      });
}

class AccountsMenuCard extends StatelessWidget {
  const AccountsMenuCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: CehTheme.paleBlue,
                    borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: CehTheme.blue, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.black54)),
                    ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
      );
}

class AccountsStatusChip extends StatelessWidget {
  const AccountsStatusChip(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    final positive = ['PAID', 'APPROVED', 'READY', 'ACTIVE', 'CONNECTED']
        .contains(label.toUpperCase());
    final warning = ['PENDING', 'PART PAID', 'OUTSTANDING', 'NEEDS RECEIPT']
        .contains(label.toUpperCase());
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: positive
          ? const Color(0xFFE3F4E8)
          : warning
              ? const Color(0xFFFFF0D7)
              : CehTheme.paleBlue,
    );
  }
}

class AccountsMetricLine extends StatelessWidget {
  const AccountsMetricLine(this.label, this.value,
      {super.key, this.prominent = false});
  final String label;
  final String value;
  final bool prominent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: prominent ? 8 : 4),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight:
                          prominent ? FontWeight.w900 : FontWeight.w500))),
          Text(value,
              style: TextStyle(
                  fontSize: prominent ? 17 : 14,
                  fontWeight: FontWeight.w900,
                  color: prominent ? CehTheme.navy : CehTheme.text)),
        ]),
      );
}

class PrototypeBanner extends StatelessWidget {
  const PrototypeBanner({super.key});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF3D6),
            borderRadius: BorderRadius.circular(12)),
        child: const Row(children: [
          Icon(Icons.science_outlined, size: 20),
          SizedBox(width: 9),
          Expanded(
              child: Text('Prototype • sample data only',
                  style: TextStyle(fontWeight: FontWeight.w800))),
        ]),
      );
}
