enum InvoiceVatMode { none, exclusive, inclusive }

class InvoiceTaxAmounts {
  const InvoiceTaxAmounts(
      {required this.netMinor,
      required this.vatMinor,
      required this.grossMinor});
  final int netMinor;
  final int vatMinor;
  final int grossMinor;
}

InvoiceTaxAmounts calculateInvoiceTax({
  required int enteredMinor,
  required int rateMillionthsOfPercent,
  required InvoiceVatMode mode,
  bool taxable = true,
}) {
  if (enteredMinor <= 0 || rateMillionthsOfPercent < 0) {
    throw ArgumentError('Invalid invoice tax input');
  }
  if (!taxable || mode == InvoiceVatMode.none) {
    return InvoiceTaxAmounts(
        netMinor: enteredMinor, vatMinor: 0, grossMinor: enteredMinor);
  }
  const denominator = 100000000;
  if (mode == InvoiceVatMode.exclusive) {
    final vat = (enteredMinor * rateMillionthsOfPercent + denominator ~/ 2) ~/
        denominator;
    return InvoiceTaxAmounts(
        netMinor: enteredMinor, vatMinor: vat, grossMinor: enteredMinor + vat);
  }
  final divisor = denominator + rateMillionthsOfPercent;
  final net = (enteredMinor * denominator + divisor ~/ 2) ~/ divisor;
  return InvoiceTaxAmounts(
      netMinor: net, vatMinor: enteredMinor - net, grossMinor: enteredMinor);
}

bool canBillProductionQuantity(
        {required double signed,
        required double previouslyBilled,
        required double billingNow}) =>
    signed > 0 &&
    previouslyBilled >= 0 &&
    billingNow > 0 &&
    previouslyBilled + billingNow <= signed + 0.0000001;

double effectiveBilledProductionQuantity(
    {required double originallyBilled, required double explicitlyReleased}) {
  if (originallyBilled < 0 ||
      explicitlyReleased < 0 ||
      explicitlyReleased > originallyBilled) {
    throw ArgumentError('Invalid production quantity release');
  }
  return originallyBilled - explicitlyReleased;
}
