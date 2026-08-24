<?php
declare(strict_types=1);

require_once __DIR__ . '/../../Server/billing_common.php';

function expect_same(int $expected, int $actual, string $label): void {
    if ($expected !== $actual) {
        fwrite(STDERR, sprintf("%s: expected %d, got %d\n", $label, $expected, $actual));
        exit(1);
    }
}

expect_same(
    3375000,
    billing_percent_amount(45000000, '7.500000'),
    'VAT Exclusive 450,000 at 7.50%'
);
expect_same(
    45000000,
    billing_inclusive_net(48375000, '7.500000'),
    'VAT Inclusive 483,750 at 7.50%'
);
expect_same(
    1000000000,
    billing_inclusive_net(1075000000, '7.500000'),
    'VAT Inclusive 10,750,000 at 7.50%'
);
expect_same(
    0,
    billing_multiply_divide_round_half_up(45000000, 0, 100000000),
    'VAT None'
);
expect_same(7500000, billing_rate_millionths('7.5'), 'natural VAT rate parsing');
expect_same(7500001, billing_rate_millionths('7.500001'), 'six-decimal VAT rate parsing');

echo "billing VAT math tests passed\n";
