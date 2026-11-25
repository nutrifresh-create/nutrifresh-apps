import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// =========================================================================
// NUTRIFRESH SUPABASE ADAPTER v3.0 (TAHAP 3B — AKUNTANSI RITEL, AUDIT TRAIL & BRIDGE POS<->OFFICE)
// - Query & Filter langsung di PostgreSQL (tabel relasional nf_*)
// - Delta Realtime (hanya kirim baris berubah, tanpa unduh ulang 1 tabel)
// - Auto-Upload Foto ke Supabase Storage (bucket: nutrifresh-media)
// - Atomic Stock RPC (penguncian baris PostgreSQL + Kartu Stok otomatis)
// =========================================================================

export const SUPABASE_CONFIG = {
    url: "https://dsidhlpgdanmgndrbksx.supabase.co",
    anonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRzaWRobHBnZGFubWduZHJia3N4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTUyMzU4MjksImV4cCI6MjExMDgxMTgyOX0.lMPZB67yKcaT55sJjSZG-p0QJuuEc4Tfvez3GA_GA7o"
};

export const TENANT_ID = "nutrifresh";
const ACTIVE_BRANCH_STORAGE_KEY = "nutri_active_branch_id";

export function getActiveBranchId() {
    try {
        const saved = (localStorage.getItem(ACTIVE_BRANCH_STORAGE_KEY) || "").trim();
        if (saved && /^[a-z0-9_-]{2,40}$/i.test(saved)) return saved;
    } catch (e) {
        console.warn("[NutriFresh] Baca cabang aktif:", e?.message || e);
    }
    return "cabang-1";
}

export let BRANCH_ID = getActiveBranchId();

export function setActiveBranchId(branchId) {
    const clean = String(branchId || "cabang-1").trim().toLowerCase().replace(/[^a-z0-9_-]/g, "-");
    const finalId = clean || "cabang-1";
    BRANCH_ID = finalId;
    try {
        localStorage.setItem(ACTIVE_BRANCH_STORAGE_KEY, finalId);
    } catch (e) {
        console.warn("[NutriFresh] Simpan cabang aktif:", e?.message || e);
    }
    return finalId;
}
export const STORAGE_BUCKET = "nutrifresh-media";

export const isSupabaseConfigured = () =>
    typeof SUPABASE_CONFIG.url === "string" &&
    SUPABASE_CONFIG.url.startsWith("https://") &&
    !SUPABASE_CONFIG.url.includes("GANTI-PROJECT-ID-ANDA") &&
    typeof SUPABASE_CONFIG.anonKey === "string" &&
    SUPABASE_CONFIG.anonKey.length > 20 &&
    !SUPABASE_CONFIG.anonKey.includes("GANTI-ANON-PUBLIC-KEY-ANDA");

export const supabase = isSupabaseConfigured()
    ? createClient(SUPABASE_CONFIG.url, SUPABASE_CONFIG.anonKey, {
          auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      })
    : null;

// Helper konversi tipe aman untuk kolom terindeks
const toNum = (v, fb = 0) => {
    const n = Number(v);
    return Number.isFinite(n) ? n : fb;
};
const toIsoOrNull = (v) => {
    if (!v) return null;
    const s = String(v).trim();
    if (!s) return null;
    const d = new Date(s);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
};
const toLowerTrim = (v) => (v ? String(v).trim().toLowerCase() : "");

// Peta koleksi aplikasi -> tabel PostgreSQL relasional nf_*
const COLLECTION_MAP = {
    inventory: {
        table: "nf_inventory",
        fields: {
            name: "name",
            category: "category",
            unit: "unit",
            barcode: "barcode",
            price: "price",
            cost: "cost",
            stock: "stock",
            minStock: "min_stock",
            active: "active",
            img: "img_url"
        },
        extract: (d) => ({
            name: d.name ?? null,
            category: d.category ?? null,
            unit: d.unit || "Gram",
            barcode: d.barcode ?? null,
            price: toNum(d.price, 0),
            cost: toNum(d.cost, 0),
            stock: toNum(d.stock, 0),
            min_stock: toNum(d.minStock, 0),
            active: d.active !== false,
            img_url: d.img ?? null
        })
    },
    transactions: {
        table: "nf_transactions",
        fields: {
            branchId: "branch_id",
            date: "tx_date",
            cashier: "cashier",
            salesChannel: "channel",
            paymentMethod: "payment_method",
            customerName: "customer_name",
            customerPhone: "customer_phone",
            total: "total",
            grossProfit: "profit",
            profit: "profit",
            status: "status"
        },
        extract: (d) => ({
            tx_date: toIsoOrNull(d.date),
            cashier: d.cashier ?? null,
            channel: d.salesChannel ?? null,
            payment_method: d.paymentMethod ?? null,
            customer_name: d.customerName ?? null,
            customer_phone: d.customerPhone ?? null,
            total: toNum(d.total, 0),
            profit: toNum(d.grossProfit ?? d.profit, 0),
            status: d.status || "success"
        })
    },
    employees: {
        table: "nf_employees",
        fields: {
            name: "name",
            email: "email",
            phone: "phone",
            role: "role",
            branch: "branch",
            status: "status"
        },
        extract: (d) => ({
            name: d.name ?? null,
            email: toLowerTrim(d.email),
            phone: d.phone ?? null,
            role: d.role ?? null,
            branch: d.branch || "Cabang 1 - Cilacap Tengah",
            status: d.status || "Aktif"
        })
    },
    attendance: {
        table: "nf_attendance",
        fields: {
            branchId: "branch_id",
            dateStr: "date_str",
            employeeId: "employee_id",
            employeeName: "employee_name",
            shiftName: "shift_name",
            clockInTime: "clock_in_time",
            clockOutTime: "clock_out_time",
            status: "status"
        },
        extract: (d) => ({
            date_str: d.dateStr ?? null,
            employee_id: d.employeeId ?? null,
            employee_name: d.employeeName ?? null,
            shift_name: d.shiftName ?? null,
            clock_in_time: toIsoOrNull(d.clockInTime),
            clock_out_time: toIsoOrNull(d.clockOutTime),
            status: d.status ?? null,
            ...(d.photoInUrl ? { photo_in_url: d.photoInUrl } : {}),
            ...(d.photoOutUrl ? { photo_out_url: d.photoOutUrl } : {})
        })
    },
    members: {
        table: "nf_members",
        fields: {
            phone: "phone",
            email: "email",
            name: "name",
            points: "points",
            visits: "visits",
            totalSpend: "total_spend"
        },
        extract: (d) => ({
            phone: d.phone ?? null,
            email: toLowerTrim(d.email),
            name: d.name ?? null,
            points: Math.round(toNum(d.points, 0)),
            visits: Math.round(toNum(d.visits, 0)),
            total_spend: toNum(d.totalSpend, 0),
            address: d.address ?? null,
            address_note: d.addressNote ?? null,
            member_code: d.memberCode ?? null,
            tier: d.tier ?? "Fresh"
        })
    },
    suppliers: {
        table: "nf_suppliers",
        fields: { name: "name", phone: "phone" },
        extract: (d) => ({ name: d.name ?? null, phone: d.phone ?? null })
    },
    purchases: {
        table: "nf_purchases",
        fields: {
            branchId: "branch_id",
            date: "purchase_date",
            supplierName: "supplier_name",
            supplier: "supplier_name",
            productId: "product_id",
            totalCost: "total_cost",
            paymentStatus: "payment_status",
            dueDate: "due_date"
        },
        extract: (d) => ({
            purchase_date: toIsoOrNull(d.date),
            supplier_name: d.supplierName ?? d.supplier ?? null,
            product_id: d.productId ?? null,
            total_cost: toNum(d.totalCost, 0),
            payment_status: d.paymentStatus || "Lunas",
            due_date: d.dueDate ?? null
        })
    },
    expenses: {
        table: "nf_expenses",
        fields: {
            branchId: "branch_id",
            date: "expense_date",
            cashier: "cashier",
            desc: "description",
            amount: "amount"
        },
        extract: (d) => ({
            expense_date: toIsoOrNull(d.date),
            cashier: d.cashier ?? null,
            description: d.desc ?? null,
            amount: toNum(d.amount, 0)
        })
    },
    waste_logs: {
        table: "nf_waste_logs",
        fields: {
            branchId: "branch_id",
            date: "waste_date",
            productId: "product_id",
            productName: "product_name",
            qty: "qty",
            totalLoss: "loss_cost",
            lossCost: "loss_cost"
        },
        extract: (d) => ({
            waste_date: toIsoOrNull(d.date),
            product_id: d.productId ?? null,
            product_name: d.productName ?? null,
            qty: toNum(d.qty, 0),
            loss_cost: toNum(d.totalLoss ?? d.lossCost, 0)
        })
    },
    shift_logs: {
        table: "nf_shift_logs",
        fields: {
            branchId: "branch_id",
            openedAt: "opened_at",
            closedAt: "closed_at",
            cashierName: "cashier",
            cashier: "cashier",
            expectedCash: "expected_cash",
            actualCash: "actual_cash",
            discrepancy: "discrepancy"
        },
        extract: (d) => ({
            opened_at: toIsoOrNull(d.openedAt),
            closed_at: toIsoOrNull(d.closedAt),
            cashier: d.cashierName ?? d.cashier ?? null,
            expected_cash: toNum(d.expectedCash, 0),
            actual_cash: toNum(d.actualCash, 0),
            discrepancy: toNum(d.discrepancy, 0)
        })
    },
    supply_usages: {
        table: "nf_supply_usages",
        fields: {
            branchId: "branch_id",
            date: "usage_date",
            itemId: "item_id",
            productId: "item_id",
            itemName: "item_name",
            productName: "item_name",
            qty: "qty"
        },
        extract: (d) => ({
            usage_date: toIsoOrNull(d.date),
            item_id: d.itemId ?? d.productId ?? null,
            item_name: d.itemName ?? d.productName ?? null,
            qty: toNum(d.qty, 0)
        })
    },
    settings: {
        table: "nf_settings",
        fields: {},
        extract: () => ({})
    },
    staff_roles: {
        table: "nf_staff_roles",
        fields: {
            email: "email",
            employeeId: "employee_id",
            role: "role",
            isOwner: "is_owner",
            active: "active"
        },
        extract: (d) => ({
            email: toLowerTrim(d.email),
            employee_id: d.employeeId ?? null,
            role: d.role ?? null,
            is_owner: !!d.isOwner,
            active: d.active !== false
        })
    },
    stock_movements: {
        table: "nf_stock_movements",
        fields: {
            productId: "product_id",
            createdAt: "created_at"
        },
        extract: () => ({})
    },
    audit_logs: {
        table: "nf_audit_logs",
        fields: {
            createdAt: "created_at",
            action: "action",
            entityType: "entity_type",
            entityId: "entity_id"
        },
        extract: () => ({})
    },
    // 6 Tabel Terpisah untuk NutriFresh Office (Anti-Timpa antar Owner/Bendahara/HR)
    office_cashbook: {
        table: "nf_office_cashbook",
        fields: {
            branchId: "branch_id",
            date: "entry_date",
            kind: "kind",
            category: "category",
            note: "note",
            amount: "amount"
        },
        extract: (d) => ({
            entry_date: d.date ?? null,
            kind: d.kind ?? null,
            category: d.category ?? null,
            note: d.note ?? null,
            amount: toNum(d.amount, 0)
        })
    },
    office_debts: {
        table: "nf_office_debts",
        fields: {
            branchId: "branch_id",
            type: "debt_type",
            party: "party",
            dueDate: "due_date",
            amount: "amount",
            status: "status"
        },
        extract: (d) => ({
            debt_type: d.type ?? null,
            party: d.party ?? null,
            due_date: d.dueDate ?? null,
            amount: toNum(d.amount, 0),
            status: d.status || "Belum Lunas",
            note: d.note ?? null
        })
    },
    office_assets: {
        table: "nf_office_assets",
        fields: {
            name: "name",
            purchaseDate: "purchase_date",
            lifeMonths: "life_months",
            cost: "cost",
            salvage: "salvage"
        },
        extract: (d) => ({
            name: d.name ?? null,
            purchase_date: d.purchaseDate ?? null,
            life_months: Math.max(1, Math.round(toNum(d.lifeMonths, 12))),
            cost: toNum(d.cost, 0),
            salvage: toNum(d.salvage, 0)
        })
    },
    office_hr_requests: {
        table: "nf_office_hr_requests",
        fields: {
            empName: "emp_name",
            type: "req_type",
            date: "req_date",
            status: "status",
            hours: "hours",
            cashAmount: "cash_amount"
        },
        extract: (d) => ({
            emp_name: d.empName ?? null,
            req_type: d.type ?? null,
            req_date: d.date ?? null,
            status: d.status || "Menunggu",
            hours: toNum(d.hours, 0),
            cash_amount: toNum(d.cashAmount, 0),
            note: d.note ?? null
        })
    },
    office_payroll: {
        table: "nf_office_payroll",
        fields: {
            ym: "ym",
            empName: "emp_name",
            base: "base_salary",
            allowance: "allowance",
            isPaid: "is_paid"
        },
        extract: (d) => ({
            ym: d.ym ?? null,
            emp_name: d.empName ?? null,
            base_salary: toNum(d.base, 1500000),
            allowance: toNum(d.allowance, 0),
            is_paid: !!d.isPaid
        })
    },
    point_rewards: {
        table: "nf_point_rewards",
        fields: {
            title: "title",
            rewardType: "reward_type",
            pointsCost: "points_cost",
            discountRp: "discount_rp",
            productId: "product_id",
            productName: "product_name",
            minSpend: "min_spend",
            validDays: "valid_days",
            active: "active"
        },
        extract: (d) => ({
            title: d.title ?? "Hadiah Poin",
            description: d.description ?? "",
            reward_type: d.rewardType || "voucher_rp",
            points_cost: Math.max(1, Math.round(toNum(d.pointsCost, 100))),
            discount_rp: Math.max(0, Math.round(toNum(d.discountRp, 0))),
            product_id: d.productId ?? "",
            product_name: d.productName ?? "",
            min_spend: Math.max(0, Math.round(toNum(d.minSpend, 0))),
            valid_days: Math.max(1, Math.round(toNum(d.validDays, 30))),
            active: d.active !== false
        })
    },
    member_vouchers: {
        table: "nf_member_vouchers",
        fields: {
            memberId: "member_id",
            memberPhone: "member_phone",
            voucherCode: "voucher_code",
            status: "status"
        },
        extract: (d) => ({
            member_id: d.memberId ?? "",
            member_phone: d.memberPhone ?? "",
            reward_id: d.rewardId ?? null,
            voucher_code: d.voucherCode ?? "",
            title: d.title ?? "Voucher",
            reward_type: d.rewardType || "voucher_rp",
            discount_rp: Math.round(toNum(d.discountRp, 0)),
            product_id: d.productId ?? "",
            product_name: d.productName ?? "",
            min_spend: Math.round(toNum(d.minSpend, 0)),
            points_spent: Math.round(toNum(d.pointsSpent, 0)),
            status: d.status || "active",
            expires_at: toIsoOrNull(d.expiresAt),
            used_at: toIsoOrNull(d.usedAt),
            used_tx_id: d.usedTxId ?? null
        })
    },
    point_ledger: {
        table: "nf_point_ledger",
        fields: {
            memberId: "member_id",
            memberPhone: "member_phone",
            entryType: "entry_type",
            createdAt: "created_at"
        },
        extract: (d) => ({
            member_id: d.memberId ?? "",
            member_phone: d.memberPhone ?? "",
            delta_points: Math.round(toNum(d.deltaPoints, 0)),
            balance_before: Math.round(toNum(d.balanceBefore, 0)),
            balance_after: Math.round(toNum(d.balanceAfter, 0)),
            entry_type: d.entryType || "earn",
            ref_id: d.refId ?? "",
            note: d.note ?? "",
            actor: d.actor ?? "Sistem"
        })
    },
    resellers: {
        table: "nf_resellers",
        fields: {
            name: "name",
            shopName: "shop_name",
            phone: "phone",
            status: "status",
            totalOrders: "total_orders",
            totalSpend: "total_spend"
        },
        extract: (d) => ({
            name: d.name ?? "Reseller",
            shop_name: d.shopName ?? "",
            phone: d.phone ?? "",
            address: d.address ?? "",
            notes: d.notes ?? "",
            status: d.status || "Aktif",
            total_orders: Math.round(toNum(d.totalOrders, 0)),
            total_spend: toNum(d.totalSpend, 0)
        })
    },
    office_config: {
        table: "nf_office_config",
        fields: {},
        extract: () => ({})
    },
    parcel_orders: {
        table: "nf_parcel_orders",
        fields: {
            branchId: "branch_id",
            orderCode: "order_code",
            customerName: "customer_name",
            customerPhone: "customer_phone",
            institution: "institution",
            memberId: "member_id",
            source: "source",
            deliveryDate: "delivery_date",
            deliveryTime: "delivery_time",
            totalAmount: "total_amount",
            dpAmount: "dp_amount",
            paymentStatus: "payment_status",
            orderStatus: "order_status",
            linkedTxId: "linked_tx_id",
            createdAt: "created_at"
        },
        extract: (d) => ({
            order_code: d.orderCode || d.id || "",
            customer_name: d.customerName || "Pelanggan",
            customer_phone: d.customerPhone || "-",
            institution: d.institution || "",
            member_id: d.memberId || null,
            source: d.source || "pos",
            delivery_date: d.deliveryDate || new Date().toISOString().slice(0, 10),
            delivery_time: d.deliveryTime || "08:00",
            total_amount: toNum(d.totalAmount, 0),
            dp_amount: toNum(d.dpAmount, 0),
            payment_status: d.paymentStatus || "Belum Bayar",
            order_status: d.orderStatus || "Dikonfirmasi",
            linked_tx_id: d.linkedTxId || null,
            items: Array.isArray(d.items) ? d.items : []
        })
    },
    online_orders: {
        table: "nf_online_orders",
        fields: {
            branchId: "branch_id",
            orderCode: "order_code",
            receiptToken: "receipt_token",
            customerName: "customer_name",
            customerPhone: "customer_phone",
            deliveryMode: "delivery_mode",
            paymentMethod: "payment_method",
            orderStatus: "order_status",
            linkedTxId: "linked_tx_id",
            createdAt: "created_at"
        },
        extract: (d) => ({
            order_code: d.orderCode || d.id || "",
            receipt_token: d.receiptToken || "",
            customer_name: d.customerName || "Pelanggan",
            customer_phone: d.customerPhone || "-",
            delivery_mode: d.deliveryMode || "Kirim ke Rumah",
            address: d.address || "",
            payment_method: d.paymentMethod || "QRIS",
            voucher_code: d.voucherCode || "",
            voucher_title: d.voucherTitle || "",
            member_id: d.memberId || null,
            estimated_total: toNum(d.estimatedTotal, 0),
            final_total: toNum(d.finalTotal ?? d.estimatedTotal, 0),
            order_status: d.orderStatus || "Menunggu Timbang",
            linked_tx_id: d.linkedTxId || null,
            shipping_fee: toNum(d.shippingFee, 0),
            ...(d.weighPhotoUrl ? { weigh_photo_url: d.weighPhotoUrl } : {}),
            ...(d.paymentProofUrl ? { payment_proof_url: d.paymentProofUrl } : {}),
            ...(d.cashierNote !== undefined ? { cashier_note: String(d.cashierNote || "") } : {}),
            status_updated_at: new Date().toISOString(),
            items: Array.isArray(d.items) ? d.items : []
        })
    },
    hr_announcements: {
        table: "nf_hr_announcements",
        fields: {
            branchId: "branch_id",
            title: "title",
            priority: "priority",
            active: "active",
            createdAt: "created_at"
        },
        extract: (d) => ({
            title: d.title || "",
            body: d.body || "",
            priority: d.priority || "info",
            active: d.active !== false,
            created_by: d.createdBy || null,
            created_at: toIsoOrNull(d.createdAt) || new Date().toISOString()
        })
    },
    hr_schedules: {
        table: "nf_hr_schedules",
        fields: {
            branchId: "branch_id",
            date: "sched_date",
            schedDate: "sched_date",
            employeeId: "employee_id",
            employeeName: "employee_name",
            shiftName: "shift_name"
        },
        extract: (d) => ({
            sched_date: d.date || d.schedDate || "",
            employee_id: d.employeeId || null,
            employee_name: d.employeeName || "",
            shift_name: d.shiftName || "Shift 1",
            note: d.note || ""
        })
    },
    hr_loans: {
        table: "nf_hr_loans",
        fields: {
            branchId: "branch_id",
            employeeId: "employee_id",
            employeeName: "employee_name",
            date: "loan_date",
            status: "status"
        },
        extract: (d) => ({
            employee_id: d.employeeId || null,
            employee_name: d.employeeName || "",
            loan_date: d.date || d.loanDate || "",
            total_amount: toNum(d.totalAmount, 0),
            paid_amount: toNum(d.paidAmount, 0),
            monthly_installment: toNum(d.monthlyInstallment, 0),
            status: d.status || "Aktif",
            note: d.note || ""
        })
    },
    hr_leave_quotas: {
        table: "nf_hr_leave_quotas",
        fields: {
            branchId: "branch_id",
            year: "year",
            employeeId: "employee_id",
            employeeName: "employee_name"
        },
        extract: (d) => ({
            year: Math.round(toNum(d.year, new Date().getFullYear())),
            employee_id: d.employeeId || null,
            employee_name: d.employeeName || "",
            annual_quota: Math.round(toNum(d.annualQuota, 12)),
            used_days: Math.round(toNum(d.usedDays, 0))
        })
    }
};

function getTableMeta(colName) {
    return COLLECTION_MAP[colName] || null;
}

function rowToItem(row) {
    if (!row) return null;
    const base = row.data && typeof row.data === "object" ? { ...row.data } : {};
    if (row.id !== undefined) base.id = row.id;
    // Pastikan field stok/harga/gambar yang mungkin diubah via RPC selalu sinkron dengan kolom teratas
    if ("stock" in row && row.stock !== null && row.stock !== undefined) base.stock = Number(row.stock);
    if ("cost" in row && row.cost !== null && row.cost !== undefined) base.cost = Number(row.cost);
    if ("price" in row && row.price !== null && row.price !== undefined) base.price = Number(row.price);
    if ("active" in row && row.active !== null && row.active !== undefined && !("is_owner" in row)) base.active = !!row.active;
    if ("img_url" in row && row.img_url) base.img = row.img_url;
    if ("branch_id" in row && row.branch_id) base.branchId = row.branch_id;
    if ("photo_in_url" in row && row.photo_in_url) base.photoInUrl = row.photo_in_url;
    if ("photo_out_url" in row && row.photo_out_url) base.photoOutUrl = row.photo_out_url;
    if ("shipping_fee" in row && row.shipping_fee !== null && row.shipping_fee !== undefined) base.shippingFee = Number(row.shipping_fee);
    if ("weigh_photo_url" in row && row.weigh_photo_url) base.weighPhotoUrl = row.weigh_photo_url;
    if ("payment_proof_url" in row && row.payment_proof_url) base.paymentProofUrl = row.payment_proof_url;
    if ("cashier_note" in row && row.cashier_note) base.cashierNote = row.cashier_note;
    return base;
}

function matchWhereConstraint(item, c) {
    const v = item[c.field];
    if (c.op === "==") return v === c.value;
    if (c.op === "!=") return v !== c.value;
    if (c.op === ">") return v > c.value;
    if (c.op === ">=") return v >= c.value;
    if (c.op === "<") return v < c.value;
    if (c.op === "<=") return v <= c.value;
    return true;
}

function applyConstraintsInMemory(items, constraints = []) {
    let res = [...items];
    for (const c of constraints) {
        if (c._type === "where") {
            res = res.filter((item) => matchWhereConstraint(item, c));
        }
    }
    for (const c of constraints) {
        if (c._type === "orderBy") {
            const mult = c.dir === "desc" ? -1 : 1;
            res.sort((a, b) => {
                const va = a[c.field] ?? "";
                const vb = b[c.field] ?? "";
                if (va < vb) return -1 * mult;
                if (va > vb) return 1 * mult;
                return 0;
            });
        }
    }
    for (const c of constraints) {
        if (c._type === "limit") {
            res = res.slice(0, c.n);
        }
    }
    return res;
}

// =========================================================================
// SUPABASE STORAGE: AUTO-UPLOAD DATA URL FOTO -> PUBLIC URL RINGAN
// =========================================================================

function dataUrlToBlob(dataUrl) {
    const parts = String(dataUrl).split(",");
    if (parts.length < 2) return null;
    const mimeMatch = parts[0].match(/data:([^;]+);base64/i);
    const mime = mimeMatch ? mimeMatch[1] : "image/jpeg";
    const binStr = atob(parts[1]);
    const len = binStr.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = binStr.charCodeAt(i);
    return new Blob([bytes], { type: mime });
}

export async function uploadDataUrlToStorage(dataUrl, folder = "misc", filePrefix = "img") {
    if (!dataUrl || typeof dataUrl !== "string") return dataUrl || "";
    if (!dataUrl.startsWith("data:image/")) return dataUrl;
    if (!supabase) return dataUrl;

    try {
        const blob = dataUrlToBlob(dataUrl);
        if (!blob) return dataUrl;
        const ext = blob.type.includes("png") ? "png" : (blob.type.includes("webp") ? "webp" : "jpg");
        const safePrefix = String(filePrefix || "img").replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 48);
        const filePath = `${TENANT_ID}/${folder}/${safePrefix}_${Date.now()}.${ext}`;

        const { error } = await supabase.storage
            .from(STORAGE_BUCKET)
            .upload(filePath, blob, { contentType: blob.type, upsert: true, cacheControl: "31536000" });

        if (error) {
            console.warn("[NutriFresh Storage] Gagal upload, memakai fallback lokal:", error.message);
            return dataUrl;
        }
        const { data: pub } = supabase.storage.from(STORAGE_BUCKET).getPublicUrl(filePath);
        return pub?.publicUrl || dataUrl;
    } catch (err) {
        console.warn("[NutriFresh Storage] Exception upload:", err);
        return dataUrl;
    }
}

async function offloadImagesInPayload(colName, docId, payload) {
    if (!payload || typeof payload !== "object" || !supabase) return payload;
    const copy = { ...payload };

    if (colName === "inventory" && typeof copy.img === "string" && copy.img.startsWith("data:image/")) {
        copy.img = await uploadDataUrlToStorage(copy.img, "products", docId || "prd");
    }

    if (colName === "transactions" && typeof copy.paymentProofImg === "string" && copy.paymentProofImg.startsWith("data:image/")) {
        copy.paymentProofImg = await uploadDataUrlToStorage(copy.paymentProofImg, "proofs", docId || "trx");
    }

    if (colName === "settings" && docId === "store_settings" && Array.isArray(copy.promoSlides)) {
        const nextSlides = [];
        for (let i = 0; i < copy.promoSlides.length; i++) {
            const slide = { ...copy.promoSlides[i] };
            if (typeof slide.imgData === "string" && slide.imgData.startsWith("data:image/")) {
                slide.imgData = await uploadDataUrlToStorage(slide.imgData, "banners", `slide_${i}`);
            }
            nextSlides.push(slide);
        }
        copy.promoSlides = nextSlides;
    }
    if (colName === "settings" && docId === "store_settings" && typeof copy.qrisImg === "string" && copy.qrisImg.startsWith("data:image/")) {
        copy.qrisImg = await uploadDataUrlToStorage(copy.qrisImg, "banners", "qris_store");
    }
    if (colName === "online_orders" && typeof copy.weighPhotoUrl === "string" && copy.weighPhotoUrl.startsWith("data:image/")) {
        copy.weighPhotoUrl = await uploadDataUrlToStorage(copy.weighPhotoUrl, "proofs", (docId || "ord") + "_weigh");
    }

    return copy;
}

export async function migrateLegacyImagesToStorage() {
    if (!supabase) return { products: 0, banners: 0, proofs: 0 };
    const counts = { products: 0, banners: 0, proofs: 0 };

    // 1. Foto Produk Base64 di nf_inventory
    const { data: invRows } = await supabase
        .from("nf_inventory")
        .select("id, img_url, data")
        .eq("tenant_id", TENANT_ID);

    for (const row of invRows || []) {
        const rawImg = row.img_url || row.data?.img || "";
        if (typeof rawImg === "string" && rawImg.startsWith("data:image/")) {
            const url = await uploadDataUrlToStorage(rawImg, "products", row.id);
            if (url.startsWith("http")) {
                const nextData = { ...(row.data || {}), img: url };
                await supabase
                    .from("nf_inventory")
                    .update({ img_url: url, data: nextData, updated_at: new Date().toISOString() })
                    .eq("tenant_id", TENANT_ID)
                    .eq("id", row.id);
                counts.products++;
            }
        }
    }

    // 2. Poster Banner Promo di nf_settings/store_settings
    const { data: setRow } = await supabase
        .from("nf_settings")
        .select("id, data")
        .eq("tenant_id", TENANT_ID)
        .eq("id", "store_settings")
        .maybeSingle();

    if (setRow?.data && Array.isArray(setRow.data.promoSlides)) {
        let changed = false;
        const slides = [];
        for (let i = 0; i < setRow.data.promoSlides.length; i++) {
            const s = { ...setRow.data.promoSlides[i] };
            if (typeof s.imgData === "string" && s.imgData.startsWith("data:image/")) {
                const url = await uploadDataUrlToStorage(s.imgData, "banners", `slide_${i}`);
                if (url.startsWith("http")) {
                    s.imgData = url;
                    changed = true;
                    counts.banners++;
                }
            }
            slides.push(s);
        }
        if (changed) {
            await supabase
                .from("nf_settings")
                .update({ data: { ...setRow.data, promoSlides: slides }, updated_at: new Date().toISOString() })
                .eq("tenant_id", TENANT_ID)
                .eq("id", "store_settings");
        }
    }

    // 3. Bukti Bayar Non-Tunai di nf_transactions
    const { data: txRows } = await supabase
        .from("nf_transactions")
        .select("id, data")
        .eq("tenant_id", TENANT_ID);

    for (const row of txRows || []) {
        const proof = row.data?.paymentProofImg || "";
        if (typeof proof === "string" && proof.startsWith("data:image/")) {
            const url = await uploadDataUrlToStorage(proof, "proofs", row.id);
            if (url.startsWith("http")) {
                const nextData = { ...(row.data || {}), paymentProofImg: url };
                await supabase
                    .from("nf_transactions")
                    .update({ data: nextData, updated_at: new Date().toISOString() })
                    .eq("tenant_id", TENANT_ID)
                    .eq("id", row.id);
                counts.proofs++;
            }
        }
    }

    return counts;
}

// =========================================================================
// RPC ATOMIC POSTGRESQL (ANTI-BENTROK STOK & KARTU STOK OTOMATIS)
// =========================================================================

export async function adjustStockAtomicRpc({
    productId,
    deltaQty,
    newUnitCost = null,
    reason = "Penyesuaian",
    refId = null,
    actor = "Sistem",
    preventNegative = false
}) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_adjust_stock_atomic", {
        p_product_id: String(productId),
        p_delta_qty: Math.round(Number(deltaQty) || 0),
        p_new_unit_cost: newUnitCost !== null && Number(newUnitCost) > 0 ? Number(newUnitCost) : null,
        p_reason: String(reason || "Penyesuaian"),
        p_ref_id: refId ? String(refId) : null,
        p_actor: String(actor || "Sistem"),
        p_prevent_negative: !!preventNegative,
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    if (data && data.product_id) {
        notifyLocalPatch("inventory", data.product_id, {
            stock: Number(data.stock_after),
            cost: Number(data.cost_after)
        });
    }
    return data;
}

export async function batchAdjustStockAtomicRpc({
    items,
    reason = "Transaksi Kasir",
    refId = null,
    actor = "Kasir",
    preventNegative = true
}) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const cleanItems = (items || []).map((it) => ({
        product_id: String(it.productId || it.product_id),
        delta_qty: Math.round(Number(it.deltaQty ?? it.delta_qty) || 0),
        ...(it.newUnitCost ? { new_unit_cost: Number(it.newUnitCost) } : {}),
        ...(it.reason ? { reason: String(it.reason) } : {})
    }));
    const { data, error } = await supabase.rpc("nf_batch_adjust_stock_atomic", {
        p_items: cleanItems,
        p_reason: String(reason || "Transaksi Kasir"),
        p_ref_id: refId ? String(refId) : null,
        p_actor: String(actor || "Kasir"),
        p_prevent_negative: !!preventNegative,
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    if (Array.isArray(data)) {
        data.forEach((res) => {
            if (res && res.product_id) {
                notifyLocalPatch("inventory", res.product_id, {
                    stock: Number(res.stock_after),
                    cost: Number(res.cost_after)
                });
            }
        });
    }
    return data;
}

export async function getServerTimestampRpc() {
    if (!supabase) return new Date().toISOString();
    const { data, error } = await supabase.rpc("nf_server_now");
    if (error || !data) return new Date().toISOString();
    return String(data);
}

// =========================================================================
// RPC KEAMANAN SERVER, VERIFIKASI PIN BCRYPT & ABSENSI JAM SERVER (TAHAP 2B)
// =========================================================================

export async function getMyStaffProfileRpc() {
    if (!supabase) return { is_authenticated: false, is_owner: false, is_staff: false, owner_configured: false };
    const { data, error } = await supabase.rpc("nf_get_my_staff_profile", { p_tenant_id: TENANT_ID });
    if (error) throw error;
    return data || { is_authenticated: false, is_owner: false, is_staff: false, owner_configured: false };
}

export async function verifyEmployeePinRpc(employeeId, pin) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_verify_employee_pin", {
        p_employee_id: String(employeeId),
        p_pin: String(pin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data || { ok: false, reason: "Verifikasi gagal." };
}

export async function setEmployeePinRpc(employeeId, pin) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_set_employee_pin", {
        p_employee_id: String(employeeId),
        p_pin: String(pin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data || { ok: false };
}

export async function verifyOwnerPinRpc(pin) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_verify_owner_pin", {
        p_pin: String(pin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data || { ok: false };
}

export async function setOwnerSecurityRpc(ownerEmail, newPin = null) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_set_owner_security", {
        p_owner_email: String(ownerEmail || "").trim().toLowerCase(),
        p_new_pin: newPin ? String(newPin).trim() : null,
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data || { ok: false };
}

export async function lookupMemberByPhoneRpc(phone) {
    if (!supabase) return null;
    const { data, error } = await supabase.rpc("nf_lookup_member_by_phone", {
        p_phone: String(phone || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) return null;
    return data || null;
}

export async function clockInServerRpc({
    employeeId,
    employeeName,
    employeeRole,
    shiftName,
    lat,
    lng,
    note = "-",
    deviceId = ""
}) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_clock_in_server", {
        p_employee_id: String(employeeId),
        p_employee_name: String(employeeName || "Karyawan"),
        p_employee_role: String(employeeRole || "Karyawan"),
        p_shift_name: String(shiftName || "Shift 1"),
        p_lat: Number(lat),
        p_lng: Number(lng),
        p_note: String(note || "-"),
        p_device_id: String(deviceId || ""),
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    if (data && data.id) {
        notifyLocalListeners("attendance", "UPSERT", data.id, data);
    }
    return data;
}

export async function clockOutServerRpc({ employeeId, lat, lng }) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_clock_out_server", {
        p_employee_id: String(employeeId),
        p_lat: Number(lat),
        p_lng: Number(lng),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    if (data && data.id) {
        notifyLocalListeners("attendance", "UPSERT", data.id, data);
    }
    return data;
}

// Bersihkan seluruh data sensitif (PIN, pegawai, keuangan, transaksi, sesi staf) dari perangkat bersama
const SENSITIVE_STORAGE_KEYS = [
    "nutri_staff_session_hint",
    "nutri_terminal_active_employee",
    "nutrifresh_offline_emp",
    "nutrifresh_offline_tx",
    "nutrifresh_offline_att",
    "nutrifresh_offline_exp",
    "nutrifresh_offline_pur",
    "nutrifresh_offline_waste",
    "nutrifresh_offline_shifts",
    "nutrifresh_offline_supply",
    "nutrifresh_offline_sup",
    "nutrifresh_offline_crm",
    "nutrifresh_offline_sec",
    "nutri_cash_shift",
    "nutrifresh_office_suite_v2",
    "nutrifresh_employees",
    "employees"
];

export function clearSensitiveLocalStorage() {
    for (const k of SENSITIVE_STORAGE_KEYS) {
        try { localStorage.removeItem(k); } catch (e) { console.warn("[NutriFresh] Gagal hapus cache lokal:", k, e?.message || e); }
    }
    try { sessionStorage.removeItem("nutri_entry_choice_done"); } catch (e) { console.warn("[NutriFresh] Gagal reset sessionStorage:", e?.message || e); }
}

// =========================================================================
// RPC AKUNTANSI RITEL, AUDIT TRAIL, KARTU STOK & BRIDGE POS <-> OFFICE (TAHAP 3B)
// =========================================================================

export async function logAuditEventRpc({
    action,
    entityType,
    entityId = "",
    summary = "",
    reason = "-",
    actorName = "Sistem",
    actorRole = "",
    payload = {}
}) {
    if (!supabase) return { ok: false };
    try {
        const { data, error } = await supabase.rpc("nf_log_audit_event", {
            p_action: String(action || "INFO"),
            p_entity_type: String(entityType || "system"),
            p_entity_id: String(entityId || ""),
            p_summary: String(summary || ""),
            p_reason: String(reason || "-"),
            p_actor_name: String(actorName || "Sistem"),
            p_actor_role: String(actorRole || ""),
            p_payload: payload || {},
            p_tenant_id: TENANT_ID,
            p_branch_id: getActiveBranchId()
        });
        if (error) {
            console.warn("[NutriFresh Audit] Gagal catat audit:", error.message);
            return { ok: false, error };
        }
        return data || { ok: true };
    } catch (e) {
        return { ok: false, error: e };
    }
}

export async function fetchAuditLogsRpc(limitCount = 150) {
    if (!supabase) return [];
    const { data, error } = await supabase
        .from("nf_audit_logs")
        .select("*")
        .eq("tenant_id", TENANT_ID)
        .order("created_at", { ascending: false })
        .limit(Math.max(1, Math.min(Number(limitCount) || 150, 300)));
    if (error) throw error;
    return data || [];
}

export async function getStockCardRpc(productId, limitCount = 120) {
    if (!supabase) return [];
    const { data, error } = await supabase.rpc("nf_get_stock_card", {
        p_product_id: String(productId),
        p_limit: Math.max(1, Math.min(Number(limitCount) || 120, 300)),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return Array.isArray(data) ? data : [];
}

export async function bridgeShiftDepositToOfficeRpc({
    shiftId,
    depositAmount,
    cashierName = "Kasir",
    note = "-",
    entryDate = null
}) {
    if (!supabase) return { ok: false, skipped: true };
    const { data, error } = await supabase.rpc("nf_bridge_shift_deposit_to_office", {
        p_shift_id: String(shiftId),
        p_deposit_amount: Math.round(Number(depositAmount) || 0),
        p_cashier_name: String(cashierName || "Kasir"),
        p_note: String(note || "-"),
        p_entry_date: entryDate || null,
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    return data || { ok: true };
}

export async function bridgeTempoPurchaseToOfficeRpc({
    purchaseId,
    supplierName,
    amount,
    dueDate,
    note = "-",
    staffName = "Staf"
}) {
    if (!supabase) return { ok: false, skipped: true };
    const { data, error } = await supabase.rpc("nf_bridge_tempo_purchase_to_office", {
        p_purchase_id: String(purchaseId),
        p_supplier_name: String(supplierName || "Supplier Umum"),
        p_amount: Math.round(Number(amount) || 0),
        p_due_date: String(dueDate || ""),
        p_note: String(note || "-"),
        p_staff_name: String(staffName || "Staf"),
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    return data || { ok: true };
}

export async function bridgeSettleTempoSyncRpc({
    purchaseId,
    actorName = "Owner"
}) {
    if (!supabase) return { ok: false };
    const { data, error } = await supabase.rpc("nf_bridge_settle_tempo_sync", {
        p_purchase_id: String(purchaseId),
        p_actor_name: String(actorName || "Owner"),
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    return data || { ok: true };
}

// =========================================================================
// ANTAMUKA KOMPATIBEL FIRESTORE-STYLE DI ATAS TABEL RELASIONAL POSTGRESQL
// =========================================================================

export function initializeApp() { return supabase; }
export function getFirestore() { return supabase; }

export function collection(_sb, ...segments) {
    return { _type: "collection", collection: String(segments[segments.length - 1]) };
}

export function doc(_sb, ...segments) {
    return {
        _type: "doc",
        collection: String(segments[segments.length - 2]),
        id: String(segments[segments.length - 1])
    };
}

export function query(colRef, ...constraints) {
    return { _type: "query", collection: colRef.collection, constraints };
}

export function where(field, op, value) { return { _type: "where", field, op, value }; }
export function orderBy(field, dir = "asc") { return { _type: "orderBy", field, dir }; }
export function limit(n) { return { _type: "limit", n }; }
export function serverTimestamp() { return new Date().toISOString(); }

export async function getDoc(docRef) {
    if (!supabase) return { exists: () => false, data: () => undefined, id: docRef.id };
    const meta = getTableMeta(docRef.collection);
    if (!meta) {
        // Fallback aman jika ada koleksi lama belum dipetakan
        const { data, error } = await supabase
            .from("nutrifresh_docs")
            .select("id, data")
            .eq("collection", docRef.collection)
            .eq("id", docRef.id)
            .maybeSingle();
        if (error) throw error;
        if (!data) return { exists: () => false, data: () => undefined, id: docRef.id };
        return { id: data.id, exists: () => true, data: () => ({ ...(data.data || {}) }) };
    }

    const { data, error } = await supabase
        .from(meta.table)
        .select("*")
        .eq("tenant_id", TENANT_ID)
        .eq("id", docRef.id)
        .maybeSingle();

    if (error) throw error;
    if (!data) return { exists: () => false, data: () => undefined, id: docRef.id };
    const item = rowToItem(data);
    return { id: data.id, exists: () => true, data: () => ({ ...item }) };
}

export async function getDocs(targetRef) {
    if (!supabase) return { empty: true, docs: [], size: 0 };
    const colName = targetRef.collection;
    const constraints = targetRef.constraints || [];
    const meta = getTableMeta(colName);

    if (!meta) {
        const { data, error } = await supabase
            .from("nutrifresh_docs")
            .select("id, data")
            .eq("collection", colName);
        if (error) throw error;
        let items = (data || []).map((r) => ({ id: r.id, ...(r.data || {}) }));
        items = applyConstraintsInMemory(items, constraints);
        const docs = items.map((it) => ({ id: it.id, exists: () => true, data: () => ({ ...it }) }));
        return { empty: docs.length === 0, size: docs.length, docs };
    }

    // Bangun query PostgreSQL asli (server-side where, orderBy, limit)
    let qb = supabase.from(meta.table).select("*").eq("tenant_id", TENANT_ID);
    const unmappedConstraints = [];

    for (const c of constraints) {
        if (c._type === "where") {
            const col = meta.fields[c.field];
            if (col) {
                const val = col === "email" ? toLowerTrim(c.value) : c.value;
                if (c.op === "==") qb = qb.eq(col, val);
                else if (c.op === "!=") qb = qb.neq(col, val);
                else if (c.op === ">") qb = qb.gt(col, val);
                else if (c.op === ">=") qb = qb.gte(col, val);
                else if (c.op === "<") qb = qb.lt(col, val);
                else if (c.op === "<=") qb = qb.lte(col, val);
            } else {
                unmappedConstraints.push(c);
            }
        }
    }

    for (const c of constraints) {
        if (c._type === "orderBy") {
            const col = meta.fields[c.field];
            if (col) {
                qb = qb.order(col, { ascending: c.dir !== "desc", nullsFirst: false });
            } else {
                unmappedConstraints.push(c);
            }
        }
    }

    // Hanya terapkan limit di server jika tidak ada filter unmapped yang perlu dihitung dulu
    const hasUnmappedWhere = unmappedConstraints.some((c) => c._type === "where");
    for (const c of constraints) {
        if (c._type === "limit") {
            if (!hasUnmappedWhere) qb = qb.limit(c.n);
            else unmappedConstraints.push(c);
        }
    }

    const { data, error } = await qb;
    if (error) throw error;

    let items = (data || []).map(rowToItem).filter(Boolean);
    if (unmappedConstraints.length > 0) {
        items = applyConstraintsInMemory(items, unmappedConstraints);
    }

    const docs = items.map((item) => ({
        id: item.id,
        exists: () => true,
        data: () => ({ ...item })
    }));
    return { empty: docs.length === 0, size: docs.length, docs };
}

export async function setDoc(docRef, payload, options = {}) {
    if (!supabase) return;
    const colName = docRef.collection;
    const docId = docRef.id;
    let finalData = { ...payload };

    if (options && options.merge) {
        const existing = await getDoc(docRef).catch(() => null);
        if (existing && existing.exists()) {
            finalData = { ...existing.data(), ...finalData };
        }
    }

    finalData = await offloadImagesInPayload(colName, docId, finalData);
    if (colName === "employees" && "pin" in finalData) {
        delete finalData.pin;
    }
    finalData.id = docId;

    const meta = getTableMeta(colName);
    if (!meta) {
        const { error } = await supabase
            .from("nutrifresh_docs")
            .upsert(
                { collection: colName, id: docId, data: finalData, updated_at: new Date().toISOString() },
                { onConflict: "collection,id" }
            );
        if (error) throw error;
        notifyLocalListeners(colName, "UPSERT", docId, finalData);
        return;
    }

    const rowPayload = {
        tenant_id: TENANT_ID,
        branch_id: (finalData && finalData.branchId) ? String(finalData.branchId) : getActiveBranchId(),
        id: docId,
        ...meta.extract(finalData),
        data: finalData,
        updated_at: new Date().toISOString()
    };

    const { error } = await supabase
        .from(meta.table)
        .upsert(rowPayload, { onConflict: "tenant_id,id" });
    if (error) throw error;

    notifyLocalListeners(colName, "UPSERT", docId, finalData);
}

export async function updateDoc(docRef, partialPayload) {
    return setDoc(docRef, partialPayload, { merge: true });
}

export async function deleteDoc(docRef) {
    if (!supabase) return;
    const colName = docRef.collection;
    const docId = docRef.id;
    const meta = getTableMeta(colName);

    if (!meta) {
        const { error } = await supabase
            .from("nutrifresh_docs")
            .delete()
            .eq("collection", colName)
            .eq("id", docId);
        if (error) throw error;
        notifyLocalListeners(colName, "DELETE", docId, null);
        return;
    }

    const { error } = await supabase
        .from(meta.table)
        .delete()
        .eq("tenant_id", TENANT_ID)
        .eq("id", docId);
    if (error) throw error;

    notifyLocalListeners(colName, "DELETE", docId, null);
}

export async function runTransaction(_sb, updateFunction) {
    const txHelper = {
        get: async (docRef) => getDoc(docRef),
        set: (docRef, data, opts) => { txHelper._ops.push(() => setDoc(docRef, data, opts)); },
        update: (docRef, data) => { txHelper._ops.push(() => updateDoc(docRef, data)); },
        delete: (docRef) => { txHelper._ops.push(() => deleteDoc(docRef)); },
        _ops: []
    };
    const result = await updateFunction(txHelper);
    for (const op of txHelper._ops) {
        await op();
    }
    return result;
}

// =========================================================================
// DELTA REALTIME ENGINE (TANPA UNDUH ULANG SELURUH TABEL)
// =========================================================================

const __localListenersByCol = {};

function notifyLocalListeners(colName, eventType, id, itemData) {
    const list = __localListenersByCol[colName] || [];
    list.forEach((handler) => {
        try { handler(eventType, id, itemData); } catch (e) { console.warn("[NutriFresh] Delta handler error:", e); }
    });
}

function notifyLocalPatch(colName, id, patchFields) {
    const list = __localListenersByCol[colName] || [];
    list.forEach((handler) => {
        try { handler("PATCH", id, patchFields); } catch (e) { console.warn("[NutriFresh] Patch handler error:", e); }
    });
}

export function onSnapshot(targetRef, onNext, onError) {
    if (!supabase) return () => {};
    const colName = targetRef.collection;
    const meta = getTableMeta(colName);
    const tableName = meta ? meta.table : "nutrifresh_docs";
    const constraints = targetRef.constraints || [];
    const whereList = constraints.filter((c) => c._type === "where");
    let active = true;

    // Cache lokal per-listener agar event realtime cukup meng-update 1 baris (delta)
    const cacheMap = new Map();
    let docCache = null;

    const emitDoc = () => {
        if (!active) return;
        if (!docCache) {
            onNext({ id: targetRef.id, exists: () => false, data: () => undefined });
        } else {
            onNext({ id: targetRef.id, exists: () => true, data: () => ({ ...docCache }) });
        }
    };

    const emitCollection = () => {
        if (!active) return;
        const sorted = applyConstraintsInMemory(Array.from(cacheMap.values()), constraints);
        const docs = sorted.map((it) => ({
            id: it.id,
            exists: () => true,
            data: () => ({ ...it })
        }));
        onNext({ empty: docs.length === 0, size: docs.length, docs });
    };

    const applyDelta = (eventType, id, itemData) => {
        if (!active || !id) return;
        if (targetRef._type === "doc") {
            if (id !== targetRef.id) return;
            if (eventType === "DELETE") {
                docCache = null;
            } else if (eventType === "PATCH" && docCache) {
                docCache = { ...docCache, ...itemData };
            } else if (itemData) {
                docCache = { ...itemData, id };
            }
            emitDoc();
            return;
        }

        if (eventType === "DELETE") {
            if (cacheMap.delete(id)) emitCollection();
            return;
        }

        let nextItem = itemData;
        if (eventType === "PATCH") {
            const existing = cacheMap.get(id);
            if (!existing) return;
            nextItem = { ...existing, ...itemData };
        }
        if (!nextItem) return;

        const matchesAll = whereList.every((w) => matchWhereConstraint(nextItem, w));
        if (matchesAll) {
            cacheMap.set(id, { ...nextItem, id });
        } else {
            cacheMap.delete(id);
        }
        emitCollection();
    };

    // Muat awal sekali saja dengan query PostgreSQL terindeks
    (async () => {
        try {
            if (targetRef._type === "doc") {
                const snap = await getDoc(targetRef);
                docCache = snap.exists() ? snap.data() : null;
                emitDoc();
            } else {
                const snap = await getDocs(targetRef);
                cacheMap.clear();
                snap.docs.forEach((d) => cacheMap.set(d.id, { ...d.data(), id: d.id }));
                emitCollection();
            }
        } catch (err) {
            if (active && typeof onError === "function") onError(err);
        }
    })();

    if (!__localListenersByCol[colName]) __localListenersByCol[colName] = [];
    __localListenersByCol[colName].push(applyDelta);

    const channelName = `nf-delta-${tableName}-${Math.random().toString(36).slice(2, 8)}`;
    const filterStr = meta ? `tenant_id=eq.${TENANT_ID}` : `collection=eq.${colName}`;
    const channel = supabase
        .channel(channelName)
        .on(
            "postgres_changes",
            { event: "*", schema: "public", table: tableName, filter: filterStr },
            (payload) => {
                if (!active) return;
                const ev = payload.eventType;
                if (ev === "DELETE") {
                    const oldId = payload.old?.id;
                    if (oldId) applyDelta("DELETE", oldId, null);
                } else if (payload.new) {
                    const item = rowToItem(payload.new);
                    if (item && item.id) applyDelta("UPSERT", item.id, item);
                }
            }
        )
        .subscribe();

    return () => {
        active = false;
        if (__localListenersByCol[colName]) {
            __localListenersByCol[colName] = __localListenersByCol[colName].filter((fn) => fn !== applyDelta);
        }
        supabase.removeChannel(channel).catch((e) => console.warn("[NutriFresh] removeChannel:", e?.message || e));
    };
}

// =========================================================================
// AUTENTIKASI SUPABASE (GOOGLE OAUTH + SESI PERSISTEN)
// =========================================================================

export class GoogleAuthProvider {
    constructor() { this.params = {}; }
    setCustomParameters(p) { this.params = { ...this.params, ...p }; }
}

function mapSupabaseUser(sbUser) {
    if (!sbUser) {
        return {
            uid: "GUEST_" + (localStorage.getItem("nutri_device_id") || "LOCAL"),
            email: "",
            displayName: "",
            isAnonymous: true,
            providerData: []
        };
    }
    const meta = sbUser.user_metadata || {};
    const email = (sbUser.email || "").trim().toLowerCase();
    const isGoogle = !!(email && (sbUser.app_metadata?.provider === "google" || (sbUser.identities || []).some((i) => i.provider === "google")));
    return {
        uid: sbUser.id,
        email,
        displayName: meta.full_name || meta.name || (email ? email.split("@")[0] : ""),
        isAnonymous: !isGoogle,
        providerData: isGoogle ? [{ providerId: "google.com", email }] : []
    };
}

const __authCallbacks = [];
const __authInstance = {
    currentUser: mapSupabaseUser(null),
    async authStateReady() {
        if (!supabase) return;
        const { data } = await supabase.auth.getSession();
        this.currentUser = mapSupabaseUser(data?.session?.user || null);
    }
};

if (supabase) {
    supabase.auth.getSession().then(({ data }) => {
        __authInstance.currentUser = mapSupabaseUser(data?.session?.user || null);
    }).catch((e) => console.warn("[NutriFresh] Auth init warning:", e?.message || e));

    supabase.auth.onAuthStateChange((_event, session) => {
        __authInstance.currentUser = mapSupabaseUser(session?.user || null);
        __authCallbacks.forEach((cb) => {
            try { cb(__authInstance.currentUser); } catch (e) { console.error("[NutriFresh] Auth callback error:", e); }
        });
    });
}

export function getAuth() { return __authInstance; }
export async function setPersistence() { return true; }
export const browserLocalPersistence = "LOCAL";

export async function signInAnonymously(authObj) {
    authObj.currentUser = mapSupabaseUser(null);
    return { user: authObj.currentUser };
}

export async function signOut(authObj) {
    if (supabase) await supabase.auth.signOut().catch((e) => console.warn("[NutriFresh] signOut warning:", e?.message || e));
    authObj.currentUser = mapSupabaseUser(null);
}

export function onAuthStateChanged(authObj, callback) {
    __authCallbacks.push(callback);
    setTimeout(async () => {
        await authObj.authStateReady();
        callback(authObj.currentUser);
    }, 30);
    return () => {
        const idx = __authCallbacks.indexOf(callback);
        if (idx > -1) __authCallbacks.splice(idx, 1);
    };
}

async function __completeNativeOAuthSession(authObj, callbackRaw) {
    const raw = String(callbackRaw || "");
    const parts = raw.includes("|||") ? raw.split("|||") : null;
    let searchStr = "";
    let hashStr = "";
    if (parts) {
        searchStr = parts[0] || "";
        hashStr = parts[1] || "";
    } else {
        try {
            const u = new URL(raw);
            searchStr = u.search || "";
            hashStr = u.hash || "";
        } catch (_) {
            const qIdx = raw.indexOf("?");
            const hIdx = raw.indexOf("#");
            if (qIdx >= 0) searchStr = raw.slice(qIdx, hIdx > qIdx ? hIdx : undefined);
            if (hIdx >= 0) hashStr = raw.slice(hIdx);
        }
    }
    const qParams = new URLSearchParams(searchStr.replace(/^\?/, ""));
    const hParams = new URLSearchParams(hashStr.replace(/^#/, ""));
    const code = qParams.get("code");
    const accessToken = hParams.get("access_token") || qParams.get("access_token");
    const refreshToken = hParams.get("refresh_token") || qParams.get("refresh_token");

    if (code) {
        const { data, error } = await supabase.auth.exchangeCodeForSession(code);
        if (error) throw error;
        const mapped = mapSupabaseUser(data?.session?.user || data?.user || null);
        authObj.currentUser = mapped;
        return { user: mapped };
    }
    if (accessToken && refreshToken) {
        const { data, error } = await supabase.auth.setSession({
            access_token: accessToken,
            refresh_token: refreshToken
        });
        if (error) throw error;
        const mapped = mapSupabaseUser(data?.session?.user || data?.user || null);
        authObj.currentUser = mapped;
        return { user: mapped };
    }
    const errDesc = hParams.get("error_description") || qParams.get("error_description") || hParams.get("error") || qParams.get("error");
    throw new Error(errDesc || "Token login Google tidak ditemukan dari browser.");
}

export async function signInWithPopup(authObj, provider) {
    if (!supabase) throw new Error("Konfigurasi Supabase belum diisi.");

    // 1. NATIVE WINDOWS DESKTOP (TAURI .EXE) — Loopback http://localhost:43821/auth-callback
    if (typeof window !== "undefined" && window.__TAURI__?.core?.invoke) {
        const redirectTo = "http://localhost:43821/auth-callback";
        const { data, error } = await supabase.auth.signInWithOAuth({
            provider: "google",
            options: {
                redirectTo,
                skipBrowserRedirect: true,
                queryParams: provider?.params || { prompt: "select_account" }
            }
        });
        if (error) throw error;
        if (!data || !data.url) throw new Error("Gagal membuat URL login Google.");
        const callbackPayload = await window.__TAURI__.core.invoke("start_google_oauth", { authUrl: data.url });
        return await __completeNativeOAuthSession(authObj, callbackPayload);
    }

    // 2. NATIVE ANDROID (CAPACITOR .APK) — External Chrome + Deep Link id.my.nutrifresh.pos://login-callback
    if (typeof window !== "undefined" && window.NfAndroidNative?.openExternalAuth) {
        const scheme = window.__NF_ANDROID_SCHEME__ || "id.my.nutrifresh.pos";
        const redirectTo = `${scheme}://login-callback`;
        const { data, error } = await supabase.auth.signInWithOAuth({
            provider: "google",
            options: {
                redirectTo,
                skipBrowserRedirect: true,
                queryParams: provider?.params || { prompt: "select_account" }
            }
        });
        if (error) throw error;
        if (!data || !data.url) throw new Error("Gagal membuat URL login Google.");
        return await new Promise((resolve, reject) => {
            const timeoutId = setTimeout(() => {
                window.__nfPendingOAuthResolve = null;
                reject(new Error("Waktu login Google habis (3 menit). Silakan coba lagi."));
            }, 180000);
            window.__nfPendingOAuthResolve = async (callbackUrl) => {
                clearTimeout(timeoutId);
                window.__nfPendingOAuthResolve = null;
                try {
                    const res = await __completeNativeOAuthSession(authObj, callbackUrl);
                    resolve(res);
                } catch (e) {
                    reject(e);
                }
            };
            try {
                window.NfAndroidNative.openExternalAuth(data.url);
            } catch (e) {
                clearTimeout(timeoutId);
                window.__nfPendingOAuthResolve = null;
                reject(e);
            }
        });
    }

    // 3. NORMAL WEB / IPHONE BROWSER (100% ASLI v133)
    const redirectTo = window.location.origin + window.location.pathname;
    const { data, error } = await supabase.auth.signInWithOAuth({
        provider: "google",
        options: {
            redirectTo,
            skipBrowserRedirect: true,
            queryParams: provider?.params || { prompt: "select_account" }
        }
    });
    if (error) throw error;
    if (!data || !data.url) throw new Error("Gagal membuka halaman login Google Supabase.");

    // Di HP / Mode Aplikasi Terpasang (PWA/APK), pop-up OAuth sering kehilangan sinyal balik ke tab asal.
    // Gunakan redirect penuh yang 100% stabil di perangkat seluler, sementara Desktop tetap memakai pop-up.
    const isStandalonePwa = (typeof window !== "undefined") && (
        window.matchMedia?.("(display-mode: standalone)").matches ||
        window.navigator?.standalone === true ||
        document.referrer.includes("android-app://")
    );
    const isMobileUa = /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent || "");
    if (isStandalonePwa || isMobileUa) {
        window.location.href = data.url;
        return new Promise(() => {});
    }

    const w = 500, h = 620;
    const left = Math.max(0, (window.screen.width - w) / 2);
    const top = Math.max(0, (window.screen.height - h) / 2);
    const popup = window.open(data.url, "NutriFreshGoogleLogin", `width=${w},height=${h},left=${left},top=${top},resizable=yes,scrollbars=yes`);

    if (!popup || popup.closed || typeof popup.closed === "undefined") {
        window.location.href = data.url;
        return new Promise(() => {});
    }

    return new Promise((resolve, reject) => {
        let done = false;
        const cleanup = () => {
            done = true;
            clearInterval(pollTimer);
            if (sub && sub.data && sub.data.subscription) sub.data.subscription.unsubscribe();
            try { if (popup && !popup.closed) popup.close(); } catch (e) { console.warn("[NutriFresh] Popup close warning:", e?.message || e); }
        };

        const sub = supabase.auth.onAuthStateChange((_ev, session) => {
            if (!done && session && session.user && session.user.email) {
                const mapped = mapSupabaseUser(session.user);
                authObj.currentUser = mapped;
                cleanup();
                resolve({ user: mapped });
            }
        });

        const pollTimer = setInterval(async () => {
            if (done) return;
            try {
                const { data: sData } = await supabase.auth.getSession();
                if (sData && sData.session && sData.session.user && sData.session.user.email) {
                    const mapped = mapSupabaseUser(sData.session.user);
                    authObj.currentUser = mapped;
                    cleanup();
                    resolve({ user: mapped });
                    return;
                }
            } catch (e) { console.warn("[NutriFresh] Polling session warning:", e?.message || e); }
            if (popup.closed) {
                setTimeout(async () => {
                    if (done) return;
                    const { data: sFinal } = await supabase.auth.getSession().catch(() => ({ data: null }));
                    if (sFinal && sFinal.session && sFinal.session.user && sFinal.session.user.email) {
                        const mapped = mapSupabaseUser(sFinal.session.user);
                        authObj.currentUser = mapped;
                        cleanup();
                        resolve({ user: mapped });
                    } else {
                        cleanup();
                        reject(new Error("Login Google dibatalkan atau jendela ditutup."));
                    }
                }, 600);
            }
        }, 700);
    });
}


// ============================================================================
// TAHAP 4: LAZY LOAD LIBRARY BERAT, ERROR TRACKING OTOMATIS & FULL BACKUP RPC
// ============================================================================
const __loadedScriptsCache = new Map();

export function loadScriptOnce(src) {
    if (__loadedScriptsCache.has(src)) return __loadedScriptsCache.get(src);
    const promise = new Promise((resolve, reject) => {
        const existing = document.querySelector(`script[src="${src}"]`);
        if (existing && existing.dataset.loaded === "1") return resolve(true);
        const s = existing || document.createElement("script");
        s.src = src;
        s.async = true;
        s.onload = () => { s.dataset.loaded = "1"; resolve(true); };
        s.onerror = () => {
            __loadedScriptsCache.delete(src);
            reject(new Error(`Gagal memuat pustaka eksternal: ${src}`));
        };
        if (!existing) document.head.appendChild(s);
    });
    __loadedScriptsCache.set(src, promise);
    return promise;
}

export async function ensureXlsxLoaded() {
    if (typeof window !== "undefined" && typeof window.XLSX !== "undefined") return window.XLSX;
    await loadScriptOnce("https://cdn.jsdelivr.net/npm/xlsx-js-style@1.2.0/dist/xlsx.bundle.js");
    if (typeof window.XLSX === "undefined") throw new Error("Modul Excel (xlsx-js-style) gagal dimuat.");
    return window.XLSX;
}

export async function ensureJsBarcodeLoaded() {
    if (typeof window !== "undefined" && typeof window.JsBarcode !== "undefined") return window.JsBarcode;
    await loadScriptOnce("https://cdn.jsdelivr.net/npm/jsbarcode@3.11.5/dist/JsBarcode.all.min.js");
    if (typeof window.JsBarcode === "undefined") throw new Error("Modul Barcode (JsBarcode) gagal dimuat.");
    return window.JsBarcode;
}

const __recentErrorKeys = new Map();
let __errorReportCount = 0;

export async function logClientErrorRpc({ page = "", context = "", message = "", stack = "", meta = {} } = {}) {
    const cleanMsg = String(message || "Unknown client error").slice(0, 500);
    const dedupKey = `${page}|${context}|${cleanMsg}`;
    const now = Date.now();
    const lastAt = __recentErrorKeys.get(dedupKey) || 0;
    if (now - lastAt < 15000 || __errorReportCount >= 20) return null;
    __recentErrorKeys.set(dedupKey, now);
    __errorReportCount++;
    console.warn(`[NutriFresh Error Tracker] ${page} :: ${context} ->`, cleanMsg);
    if (!supabase || !navigator.onLine) return null;
    try {
        const { data, error } = await supabase.rpc("nf_log_client_error", {
            p_page: String(page || window.location.pathname || ""),
            p_context: String(context || ""),
            p_message: cleanMsg,
            p_stack: String(stack || "").slice(0, 1500),
            p_user_agent: String(navigator.userAgent || "").slice(0, 250),
            p_meta: (meta && typeof meta === "object") ? meta : {}
        });
        if (error) {
            console.warn("[NutriFresh] Gagal kirim log error ke server:", error.message);
            return null;
        }
        return data;
    } catch (rpcErr) {
        console.warn("[NutriFresh] Exception saat kirim log error:", rpcErr?.message || rpcErr);
        return null;
    }
}

export function installGlobalErrorTracker(pageName = "") {
    if (typeof window === "undefined" || window.__nfErrorTrackerInstalled) return;
    window.__nfErrorTrackerInstalled = true;
    const pName = pageName || window.location.pathname || "unknown";

    window.addEventListener("error", (ev) => {
        const msg = ev?.message || ev?.error?.message || "Uncaught JS Error";
        if (/ResizeObserver loop/i.test(msg)) return;
        logClientErrorRpc({
            page: pName,
            context: "window.error",
            message: msg,
            stack: ev?.error?.stack || `${ev?.filename || ""}:${ev?.lineno || 0}:${ev?.colno || 0}`
        });
    });

    window.addEventListener("unhandledrejection", (ev) => {
        const reason = ev?.reason;
        const msg = (reason && typeof reason === "object") ? (reason.message || String(reason)) : String(reason || "Unhandled Promise Rejection");
        if (/Login Google dibatalkan/i.test(msg)) return;
        logClientErrorRpc({
            page: pName,
            context: "unhandledrejection",
            message: msg,
            stack: (reason && reason.stack) ? reason.stack : ""
        });
    });
}

export async function fetchErrorLogsRpc(limitCount = 80) {
    if (!supabase) return [];
    const { data, error } = await supabase
        .from("nf_error_logs")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(limitCount);
    if (error) throw error;
    return Array.isArray(data) ? data : [];
}

export async function exportFullBackupRpc() {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_export_full_backup");
    if (error) throw error;
    return data;
}

const BACKUP_REMINDER_KEY = "nutri_last_full_backup_at";

export function getBackupReminderState(intervalDays = 7) {
    try {
        const raw = localStorage.getItem(BACKUP_REMINDER_KEY);
        if (!raw) {
            return { neverBackedUp: true, daysSince: 999, isDue: true, lastDateText: "Belum pernah backup" };
        }
        const ts = Number(raw);
        if (!Number.isFinite(ts) || ts <= 0) {
            return { neverBackedUp: true, daysSince: 999, isDue: true, lastDateText: "Belum pernah backup" };
        }
        const daysSince = Math.floor((Date.now() - ts) / (24 * 60 * 60 * 1000));
        const d = new Date(ts);
        const lastDateText = d.toLocaleDateString("id-ID", { day: "2-digit", month: "short", year: "numeric" });
        return { neverBackedUp: false, daysSince, isDue: daysSince >= intervalDays, lastDateText };
    } catch (e) {
        console.warn("[NutriFresh] Gagal baca status pengingat backup:", e?.message || e);
        return { neverBackedUp: true, daysSince: 999, isDue: true, lastDateText: "Belum pernah backup" };
    }
}

export async function downloadFullBackupJson() {
    const backupObj = await exportFullBackupRpc();
    const now = new Date();
    const ymd = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
    const filename = `NutriFresh_FullBackup_${ymd}.json`;
    const blob = new Blob([JSON.stringify(backupObj, null, 2)], { type: "application/json;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.style.display = "none";
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    setTimeout(() => {
        if (a.parentNode) a.parentNode.removeChild(a);
        URL.revokeObjectURL(url);
    }, 1200);
    try {
        localStorage.setItem(BACKUP_REMINDER_KEY, String(Date.now()));
    } catch (e) {
        console.warn("[NutriFresh] Gagal simpan waktu backup terakhir:", e?.message || e);
    }
    const tableCount = backupObj && backupObj.tables ? Object.keys(backupObj.tables).length : 0;
    const totalRows = backupObj && backupObj.tables
        ? Object.values(backupObj.tables).reduce((s, arr) => s + (Array.isArray(arr) ? arr.length : 0), 0)
        : 0;
    return { filename, tableCount, totalRows };
}


// ============================================================================
// TAHAP 5: AGREGASI SALDO AKURAT, RENTANG TANGGAL PENUH, MAINTENANCE & MULTI-CABANG
// ============================================================================

export async function getOfficeCashSummaryRpc(branchId = null) {
    if (!supabase) return null;
    try {
        const cleanBranch = (!branchId || branchId === "ALL") ? null : String(branchId);
        const { data, error } = await supabase.rpc("nf_get_office_cash_summary", {
            p_tenant_id: TENANT_ID,
            p_branch_id: cleanBranch
        });
        if (error) {
            console.warn("[NutriFresh] nf_get_office_cash_summary belum aktif/error:", error.message);
            return null;
        }
        return data;
    } catch (err) {
        console.warn("[NutriFresh] getOfficeCashSummaryRpc:", err?.message || err);
        return null;
    }
}

export async function fetchCollectionRangeRpc(colName, { dateField = "date", startVal = null, endVal = null, branchId = null, maxRows = 3000 } = {}) {
    if (!supabase) return [];
    const meta = getTableMeta(colName);
    if (!meta) return [];
    const dbDateCol = meta.fields[dateField] || null;
    let qb = supabase.from(meta.table).select("*").eq("tenant_id", TENANT_ID);
    if (branchId && branchId !== "ALL") {
        qb = qb.eq("branch_id", String(branchId));
    }
    if (dbDateCol && startVal) qb = qb.gte(dbDateCol, startVal);
    if (dbDateCol && endVal) qb = qb.lte(dbDateCol, endVal);
    if (dbDateCol) qb = qb.order(dbDateCol, { ascending: false, nullsFirst: false });
    qb = qb.limit(Math.max(100, Math.min(Number(maxRows) || 3000, 5000)));
    const { data, error } = await qb;
    if (error) throw error;
    return (data || []).map(rowToItem).filter(Boolean);
}

export async function getStorageMaintenanceStatsRpc() {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_get_storage_maintenance_stats", {
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function cleanupOldPaymentProofsRpc(olderThanMonths = 6) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const months = Math.max(1, Math.min(parseInt(olderThanMonths, 10) || 6, 60));
    const { data, error } = await supabase.rpc("nf_cleanup_old_payment_proofs", {
        p_older_than_months: months,
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;

    // Hapus file fisik di Supabase Storage (bucket nutrifresh-media) bila URL berasal dari bucket kita
    const urls = Array.isArray(data?.removed_urls) ? data.removed_urls : [];
    const marker = `/storage/v1/object/public/${STORAGE_BUCKET}/`;
    const pathsToRemove = [];
    urls.forEach((u) => {
        const s = String(u || "");
        const idx = s.indexOf(marker);
        if (idx > -1) {
            const rel = decodeURIComponent(s.slice(idx + marker.length).split("?")[0]);
            if (rel) pathsToRemove.push(rel);
        }
    });

    let storageDeleted = 0;
    if (pathsToRemove.length > 0) {
        try {
            // Hapus per batch 50 file agar aman
            for (let i = 0; i < pathsToRemove.length; i += 50) {
                const chunk = pathsToRemove.slice(i, i + 50);
                const { error: rmErr } = await supabase.storage.from(STORAGE_BUCKET).remove(chunk);
                if (!rmErr) storageDeleted += chunk.length;
                else console.warn("[NutriFresh] Storage remove warning:", rmErr.message);
            }
        } catch (stErr) {
            console.warn("[NutriFresh] Storage cleanup exception:", stErr?.message || stErr);
        }
    }

    return {
        cleaned_rows: Number(data?.cleaned_rows || 0),
        storage_files_deleted: storageDeleted,
        cutoff_date: data?.cutoff_date || null
    };
}
// =========================================================================
// TAHAP 6 — RPC LOYALTY MEMBER (WA+PIN 6 DIGIT, GOOGLE, POIN, VOUCHER, QR & RESELLER)
// =========================================================================

export async function ensureQrCodeLoaded() {
    if (typeof window !== "undefined" && typeof window.qrcode === "function") return true;
    await loadScriptOnce("https://cdn.jsdelivr.net/npm/qrcode-generator@1.4.4/qrcode.min.js", () => typeof window.qrcode === "function");
    return typeof window.qrcode === "function";
}

export async function memberRegisterPinRpc({ phone, name, pin, address = "", addressNote = "", email = "" }) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_member_register_pin", {
        p_phone: String(phone || "").trim(),
        p_name: String(name || "").trim(),
        p_pin: String(pin || "").trim(),
        p_address: String(address || "").trim(),
        p_address_note: String(addressNote || "").trim(),
        p_email: String(email || "").trim().toLowerCase(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function memberLoginPinRpc({ phone, pin }) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_member_login_pin", {
        p_phone: String(phone || "").trim(),
        p_pin: String(pin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function memberGoogleSyncRpc({ phone = "", name = "", address = "", addressNote = "" } = {}) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_member_google_sync", {
        p_phone: String(phone || "").trim(),
        p_name: String(name || "").trim(),
        p_address: String(address || "").trim(),
        p_address_note: String(addressNote || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function memberGetPortalRpc({ phone = "", pin = "" } = {}) {
    if (!supabase) return null;
    const { data, error } = await supabase.rpc("nf_member_get_portal", {
        p_phone: String(phone || "").trim(),
        p_pin: String(pin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function memberUpdateProfileRpc({ phone, name, address = "", addressNote = "", currentPin = "", newPin = "" }) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_member_update_profile", {
        p_phone: String(phone || "").trim(),
        p_name: String(name || "").trim(),
        p_address: String(address || "").trim(),
        p_address_note: String(addressNote || "").trim(),
        p_current_pin: String(currentPin || "").trim(),
        p_new_pin: String(newPin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function memberRedeemRewardRpc({ phone, rewardId, pin = "" }) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_member_redeem_reward", {
        p_phone: String(phone || "").trim(),
        p_reward_id: String(rewardId || "").trim(),
        p_pin: String(pin || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function staffResetMemberPinRpc({ memberPhone, newPin, actorName = "Owner" }) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_staff_reset_member_pin", {
        p_member_phone: String(memberPhone || "").trim(),
        p_new_pin: String(newPin || "").trim(),
        p_actor_name: String(actorName || "Owner"),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function posGetMemberDetailsRpc(queryText) {
    if (!supabase) return null;
    const { data, error } = await supabase.rpc("nf_pos_get_member_details", {
        p_query: String(queryText || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data || null;
}

export async function posSettleMemberTxRpc({
    memberPhone,
    memberName = "",
    txId,
    txTotal = 0,
    pointsRedeemed = 0,
    voucherId = "",
    pointsEarned = 0,
    cashier = "Kasir"
}) {
    if (!supabase) throw new Error("Koneksi Supabase belum aktif.");
    const { data, error } = await supabase.rpc("nf_pos_settle_member_tx", {
        p_member_phone: String(memberPhone || "").trim(),
        p_member_name: String(memberName || "").trim(),
        p_tx_id: String(txId || "").trim(),
        p_tx_total: Number(txTotal) || 0,
        p_points_redeemed: Math.max(0, Math.round(Number(pointsRedeemed) || 0)),
        p_voucher_id: String(voucherId || "").trim(),
        p_points_earned: Math.max(0, Math.round(Number(pointsEarned) || 0)),
        p_cashier: String(cashier || "Kasir"),
        p_tenant_id: TENANT_ID,
        p_branch_id: getActiveBranchId()
    });
    if (error) throw error;
    return data;
}

export async function posVoidMemberTxRpc({
    memberPhone,
    txId,
    pointsRedeemed = 0,
    pointsEarned = 0,
    voucherId = "",
    actor = "Owner"
}) {
    if (!supabase) return null;
    const { data, error } = await supabase.rpc("nf_pos_void_member_tx", {
        p_member_phone: String(memberPhone || "").trim(),
        p_tx_id: String(txId || "").trim(),
        p_points_redeemed: Math.max(0, Math.round(Number(pointsRedeemed) || 0)),
        p_points_earned: Math.max(0, Math.round(Number(pointsEarned) || 0)),
        p_voucher_id: String(voucherId || "").trim(),
        p_actor: String(actor || "Owner"),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}


// =========================================================================
// PRE-ORDER PARSEL & PAKET CUSTOM (v124)
// =========================================================================
export async function submitParcelOrderRpc({
    customerName,
    customerPhone,
    items,
    institution = "",
    note = "",
    paymentPlan = "Konfirmasi WA",
    branchId = getActiveBranchId()
}) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_submit_parcel_order", {
        p_customer_name: String(customerName || "").trim(),
        p_customer_phone: String(customerPhone || "").trim(),
        p_items: Array.isArray(items) ? items : [],
        p_institution: String(institution || "").trim(),
        p_note: String(note || "").trim(),
        p_payment_plan: String(paymentPlan || "Konfirmasi WA").trim(),
        p_branch_id: String(branchId || getActiveBranchId()),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}


// =========================================================================
// ORDER KATALOG MASUK KASIR & RESI DIGITAL ONLINE (v131)
// =========================================================================
export async function submitOnlineOrderRpc({
    customerName,
    customerPhone,
    items,
    deliveryMode = "Kirim ke Rumah",
    address = "",
    paymentMethod = "QRIS",
    voucherCode = "",
    voucherTitle = "",
    estimatedTotal = 0,
    branchId = getActiveBranchId()
}) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_submit_online_order", {
        p_customer_name: String(customerName || "").trim(),
        p_customer_phone: String(customerPhone || "").trim(),
        p_items: Array.isArray(items) ? items : [],
        p_delivery_mode: String(deliveryMode || "Kirim ke Rumah").trim(),
        p_address: String(address || "").trim(),
        p_payment_method: String(paymentMethod || "QRIS").trim(),
        p_voucher_code: String(voucherCode || "").trim(),
        p_voucher_title: String(voucherTitle || "").trim(),
        p_estimated_total: Math.max(0, Number(estimatedTotal) || 0),
        p_branch_id: String(branchId || getActiveBranchId()),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}

export async function getPublicReceiptRpc({ refId, token }) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_get_public_receipt", {
        p_ref_id: String(refId || "").trim(),
        p_token: String(token || "").trim().toUpperCase(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}


export async function attachAttendancePhotoRpc({ attendanceId, kind = "in", photoUrl = "" }) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    if (!attendanceId || !photoUrl) return { ok: false };
    const { data, error } = await supabase.rpc("nf_attach_attendance_photo", {
        p_attendance_id: String(attendanceId),
        p_kind: String(kind || "in"),
        p_photo_url: String(photoUrl),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}


// =========================================================================
// TAHAP 3 (v138) — LIVE TRACKING ORDER PELANGGAN & UPLOAD BUKTI BAYAR
// =========================================================================
export async function customerGetOrdersRpc(refs = []) {
    if (!supabase) return { ok: false, orders: [], paymentInfo: {} };
    const cleanRefs = Array.isArray(refs) ? refs.filter((r) => r && r.id && r.token).slice(0, 30) : [];
    const { data, error } = await supabase.rpc("nf_customer_get_orders", {
        p_refs: cleanRefs,
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data || { ok: true, orders: [], paymentInfo: {} };
}

export async function customerUploadOrderProofRpc({ orderId, token, proofUrl, paymentMethod = "" }) {
    if (!supabase) throw new Error("Supabase belum terkonfigurasi.");
    const { data, error } = await supabase.rpc("nf_customer_upload_order_proof", {
        p_order_id: String(orderId || "").trim(),
        p_token: String(token || "").trim().toUpperCase(),
        p_proof_url: String(proofUrl || "").trim(),
        p_payment_method: String(paymentMethod || "").trim(),
        p_tenant_id: TENANT_ID
    });
    if (error) throw error;
    return data;
}
