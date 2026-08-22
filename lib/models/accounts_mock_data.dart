// Mock-only Accounts Phase 1 models. No backend persistence is connected.
class AccountSummary {
  const AccountSummary(this.label, this.value, this.detail);
  final String label;
  final double value;
  final String detail;
}

class BillingItem {
  const BillingItem({
    required this.client,
    required this.project,
    required this.references,
    required this.totalM3,
    required this.status,
  });
  final String client;
  final String project;
  final List<String> references;
  final double totalM3;
  final String status;
}

class MockInvoice {
  const MockInvoice({
    required this.number,
    required this.client,
    required this.project,
    required this.date,
    required this.amount,
    required this.status,
  });
  final String number;
  final String client;
  final String project;
  final String date;
  final double amount;
  final String status;
}

class MockExpense {
  const MockExpense({
    required this.date,
    required this.supplier,
    required this.category,
    required this.amount,
    required this.project,
    required this.equipment,
    required this.paymentMethod,
    required this.hasReceipt,
    required this.status,
  });
  final String date;
  final String supplier;
  final String category;
  final double amount;
  final String project;
  final String equipment;
  final String paymentMethod;
  final bool hasReceipt;
  final String status;
}

class MockBankAccount {
  const MockBankAccount({
    required this.name,
    required this.currentBalance,
    required this.statementBalance,
    required this.unreconciledCount,
  });
  final String name;
  final double currentBalance;
  final double statementBalance;
  final int unreconciledCount;
}

class MockBankTransaction {
  const MockBankTransaction({
    required this.date,
    required this.description,
    required this.reference,
    required this.amount,
    required this.status,
  });
  final String date;
  final String description;
  final String reference;
  final double amount;
  final String status;
}

class PettyCashCustodian {
  const PettyCashCustodian({
    required this.name,
    required this.role,
    required this.fundsReceived,
    required this.accounted,
    required this.pendingApproval,
  });
  final String name;
  final String role;
  final double fundsReceived;
  final double accounted;
  final double pendingApproval;
  double get balance => fundsReceived - accounted;
  double get availableBalance => balance - pendingApproval;
}

class CustodianCashEntry {
  const CustodianCashEntry({
    required this.custodian,
    required this.date,
    required this.description,
    required this.amount,
    required this.type,
    required this.status,
  });
  final String custodian;
  final String date;
  final String description;
  final double amount;
  final String type;
  final String status;
}

class ProjectCosting {
  const ProjectCosting({
    required this.client,
    required this.project,
    required this.productionM3,
    required this.revenue,
    required this.diesel,
    required this.repairs,
    required this.labour,
    required this.transport,
    required this.other,
  });
  final String client;
  final String project;
  final double productionM3;
  final double revenue;
  final double diesel;
  final double repairs;
  final double labour;
  final double transport;
  final double other;
  double get totalCost => diesel + repairs + labour + transport + other;
  double get contribution => revenue - totalCost;
}

class EquipmentCosting {
  const EquipmentCosting({
    required this.name,
    required this.type,
    required this.revenue,
    required this.diesel,
    required this.repairs,
    required this.parts,
    required this.labour,
  });
  final String name;
  final String type;
  final double revenue;
  final double diesel;
  final double repairs;
  final double parts;
  final double labour;
  double get totalCost => diesel + repairs + parts + labour;
  double get profitability => revenue - totalCost;
}

class MockSupplier {
  const MockSupplier({
    required this.name,
    required this.category,
    required this.contact,
    required this.totalSpend,
    required this.isActive,
  });
  final String name;
  final String category;
  final String contact;
  final double totalSpend;
  final bool isActive;
}

class AccountsMockData {
  static const summaries = [
    AccountSummary('Cash / Bank', 18450000, 'Available across mock accounts'),
    AccountSummary('Receivables', 12875000, 'Outstanding client invoices'),
    AccountSummary(
        'Expenses This Month', 4920000, 'Mock August operating costs'),
    AccountSummary('Net Operating Position', 26405000,
        'Cash plus receivables less expenses'),
  ];

  static const readyToInvoice = [
    BillingItem(
        client: 'ABC Construction Ltd',
        project: 'Badagry Site',
        references: ['CEH-PR-000121', 'CEH-PR-000124'],
        totalM3: 82.5,
        status: 'Ready'),
    BillingItem(
        client: 'Julius Berger',
        project: 'Lekki Infrastructure',
        references: ['CEH-PR-000125'],
        totalM3: 37.5,
        status: 'Ready'),
    BillingItem(
        client: 'XYZ Engineering',
        project: 'Ibeju Yard',
        references: ['CEH-PR-000118'],
        totalM3: 54,
        status: 'Invoiced'),
  ];

  static const invoices = [
    MockInvoice(
        number: 'INV-1048',
        client: 'ABC Construction Ltd',
        project: 'Badagry Site',
        date: '18 Aug 2026',
        amount: 7425000,
        status: 'Outstanding'),
    MockInvoice(
        number: 'INV-1042',
        client: 'Julius Berger',
        project: 'Lekki Infrastructure',
        date: '11 Aug 2026',
        amount: 5180000,
        status: 'Part Paid'),
    MockInvoice(
        number: 'INV-1035',
        client: 'XYZ Engineering',
        project: 'Ibeju Yard',
        date: '02 Aug 2026',
        amount: 3975000,
        status: 'Paid'),
  ];

  static const expenses = [
    MockExpense(
        date: '20 Aug 2026',
        supplier: 'TotalEnergies',
        category: 'Diesel',
        amount: 685000,
        project: 'Badagry Site',
        equipment: 'Mixer 306',
        paymentMethod: 'Bank Transfer',
        hasReceipt: true,
        status: 'Approved'),
    MockExpense(
        date: '18 Aug 2026',
        supplier: 'Prime Parts Nigeria',
        category: 'Repairs & Parts',
        amount: 248500,
        project: 'Lekki Infrastructure',
        equipment: 'Pump 02',
        paymentMethod: 'Petty Cash',
        hasReceipt: true,
        status: 'Pending'),
    MockExpense(
        date: '16 Aug 2026',
        supplier: 'Ade Transport Services',
        category: 'Transport',
        amount: 175000,
        project: 'Ibeju Yard',
        equipment: 'Hiab 01',
        paymentMethod: 'Cash',
        hasReceipt: false,
        status: 'Needs Receipt'),
  ];

  static const bankAccounts = [
    MockBankAccount(
      name: 'Zenith Bank',
      currentBalance: 18450000,
      statementBalance: 18225000,
      unreconciledCount: 4,
    ),
  ];

  static const bankTransactions = [
    MockBankTransaction(
      date: '21 Aug 2026',
      description: 'Transfer to Segun — petty cash funding',
      reference: '01310',
      amount: -150000,
      status: 'Potential Match',
    ),
    MockBankTransaction(
      date: '20 Aug 2026',
      description: 'ABC Construction payment',
      reference: 'NIP-884921',
      amount: 7425000,
      status: 'Matched',
    ),
    MockBankTransaction(
      date: '19 Aug 2026',
      description: 'Transfer to Felix',
      reference: '01302',
      amount: -100000,
      status: 'Reconciled',
    ),
    MockBankTransaction(
      date: '19 Aug 2026',
      description: 'Repeated debit narration',
      reference: '01302',
      amount: -100000,
      status: 'Possible Duplicate',
    ),
    MockBankTransaction(
      date: '18 Aug 2026',
      description: 'Bank charge',
      reference: 'CHG-0826',
      amount: -2500,
      status: 'Unmatched',
    ),
  ];

  static const pettyCashCustodians = [
    PettyCashCustodian(
      name: 'Felix',
      role: 'Site Supervisor',
      fundsReceived: 100000,
      accounted: 35000,
      pendingApproval: 0,
    ),
    PettyCashCustodian(
      name: 'Segun',
      role: 'Site Supervisor',
      fundsReceived: 150000,
      accounted: 40000,
      pendingApproval: 30000,
    ),
  ];

  static const custodianCashEntries = [
    CustodianCashEntry(
      custodian: 'Felix',
      date: '20 Aug 2026',
      description: 'Workshop consumables',
      amount: 35000,
      type: 'Expense',
      status: 'Approved',
    ),
    CustodianCashEntry(
      custodian: 'Felix',
      date: '17 Aug 2026',
      description: 'Funds from Zenith Bank',
      amount: 100000,
      type: 'Funding',
      status: 'Posted',
    ),
    CustodianCashEntry(
      custodian: 'Segun',
      date: '21 Aug 2026',
      description: 'Diesel — Badagry / Mixer 307',
      amount: 30000,
      type: 'Expense',
      status: 'Pending Approval',
    ),
    CustodianCashEntry(
      custodian: 'Segun',
      date: '19 Aug 2026',
      description: 'Site transport',
      amount: 40000,
      type: 'Expense',
      status: 'Approved',
    ),
    CustodianCashEntry(
      custodian: 'Segun',
      date: '18 Aug 2026',
      description: 'Funds from Zenith Bank',
      amount: 150000,
      type: 'Funding',
      status: 'Posted',
    ),
  ];

  static const projects = [
    ProjectCosting(
        client: 'ABC Construction Ltd',
        project: 'Badagry Site',
        productionM3: 1250,
        revenue: 112500000,
        diesel: 18400000,
        repairs: 5250000,
        labour: 11800000,
        transport: 4300000,
        other: 2100000),
    ProjectCosting(
        client: 'Julius Berger',
        project: 'Lekki Infrastructure',
        productionM3: 860,
        revenue: 81700000,
        diesel: 12600000,
        repairs: 3750000,
        labour: 8400000,
        transport: 3250000,
        other: 1450000),
    ProjectCosting(
        client: 'XYZ Engineering',
        project: 'Ibeju Yard',
        productionM3: 540,
        revenue: 47250000,
        diesel: 8200000,
        repairs: 2900000,
        labour: 6100000,
        transport: 2400000,
        other: 980000),
  ];

  static const equipment = [
    EquipmentCosting(
        name: '306',
        type: 'Mixer',
        revenue: 62500000,
        diesel: 9600000,
        repairs: 2800000,
        parts: 1650000,
        labour: 4900000),
    EquipmentCosting(
        name: '307',
        type: 'Mixer',
        revenue: 48750000,
        diesel: 7900000,
        repairs: 2100000,
        parts: 1250000,
        labour: 4100000),
    EquipmentCosting(
        name: '808',
        type: 'Mixer',
        revenue: 54200000,
        diesel: 8800000,
        repairs: 2450000,
        parts: 1420000,
        labour: 4350000),
    EquipmentCosting(
        name: 'Pump 02',
        type: 'Pump',
        revenue: 17400000,
        diesel: 2200000,
        repairs: 950000,
        parts: 725000,
        labour: 1350000),
    EquipmentCosting(
        name: 'Loader 01',
        type: 'Loader',
        revenue: 9600000,
        diesel: 1950000,
        repairs: 680000,
        parts: 510000,
        labour: 840000),
    EquipmentCosting(
        name: 'Hiab 01',
        type: 'Hiab',
        revenue: 12400000,
        diesel: 2300000,
        repairs: 620000,
        parts: 430000,
        labour: 960000),
  ];

  static const suppliers = [
    MockSupplier(
        name: 'TotalEnergies',
        category: 'Fuel',
        contact: '+234 800 000 1122',
        totalSpend: 18450000,
        isActive: true),
    MockSupplier(
        name: 'Prime Parts Nigeria',
        category: 'Parts & Repairs',
        contact: 'parts@example.test',
        totalSpend: 6240000,
        isActive: true),
    MockSupplier(
        name: 'Ade Transport Services',
        category: 'Transport',
        contact: '+234 800 000 3344',
        totalSpend: 3150000,
        isActive: true),
    MockSupplier(
        name: 'Legacy Workshop Vendor',
        category: 'Workshop',
        contact: 'No current contact',
        totalSpend: 870000,
        isActive: false),
  ];
}
