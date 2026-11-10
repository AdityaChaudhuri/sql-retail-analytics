"""
Makes up a synthetic dataset for a fictional Sydney homewares retailer
("Harbour & Home") covering calendar year 2025.

It's messy on purpose - inconsistent state labels, duplicate customer
accounts, missing values, mixed-case status codes, a few invalid
quantities, orders with no line items. Basically the same stuff you'd
have to find and clean up in a real job, so there's something worth
profiling in 02_data_quality.sql.

Run:  python generate_data.py   (writes CSVs into ./data)
"""
import csv
import os
import random
from datetime import date, timedelta

random.seed(42)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
os.makedirs(OUT, exist_ok=True)

START, END = date(2025, 1, 1), date(2025, 12, 31)

FIRST = ["Olivia", "Jack", "Charlotte", "Noah", "Amelia", "William", "Isla", "Oliver",
         "Mia", "Leo", "Ava", "Henry", "Grace", "Lucas", "Chloe", "Thomas", "Zoe",
         "James", "Ruby", "Ethan", "Priya", "Arjun", "Mei", "Wei", "Hannah", "Liam",
         "Sofia", "Daniel", "Emily", "Ryan", "Aisha", "Minh", "Sarah", "Luca", "Ella"]
LAST = ["Smith", "Jones", "Williams", "Brown", "Wilson", "Taylor", "Nguyen", "Johnson",
        "Martin", "White", "Anderson", "Walker", "Thompson", "Harris", "Lee", "Ryan",
        "Robinson", "Kelly", "King", "Patel", "Chen", "Singh", "Tran", "Murphy", "Wright"]

STATES = ["NSW", "VIC", "QLD", "WA", "SA", "TAS", "ACT", "NT"]
STATE_W = [32, 26, 20, 10, 7, 2, 2, 1]
MESSY_STATE = {
    "NSW": ["nsw", "N.S.W.", "New South Wales", " NSW"],
    "VIC": ["vic", "Victoria", "Vic."],
    "QLD": ["Qld", "Queensland", "qld"],
    "WA": ["wa", "Western Australia"],
    "SA": ["sa", "South Australia"],
    "TAS": ["Tas", "Tasmania"],
    "ACT": ["act", "Canberra"],
    "NT": ["nt", "Northern Territory"],
}

# name, category, price, cost as a share of price
PRODUCTS = [
    ("Cast Iron Skillet 26cm", "Kitchen", 89.00, 0.45),
    ("Chef's Knife 20cm", "Kitchen", 129.00, 0.40),
    ("Bamboo Cutting Board", "Kitchen", 39.95, 0.35),
    ("Ceramic Dinner Set 12pc", "Kitchen", 149.00, 0.50),
    ("Glass Storage Jars (3pk)", "Kitchen", 34.95, 0.38),
    ("Linen Tea Towels (2pk)", "Kitchen", 24.95, 0.30),
    ("Pour-Over Coffee Set", "Kitchen", 64.00, 0.42),
    ("Stand Mixer Bowl Cover", "Kitchen", 14.95, 0.25),
    ("Stoneware Vase Large", "Home Decor", 79.00, 0.40),
    ("Woven Wall Hanging", "Home Decor", 119.00, 0.45),
    ("Soy Candle Eucalyptus", "Home Decor", 32.00, 0.28),
    ("Round Mirror 60cm", "Home Decor", 189.00, 0.50),
    ("Jute Floor Rug 160x230", "Home Decor", 249.00, 0.55),
    ("Ceramic Planter Set", "Home Decor", 59.00, 0.40),
    ("Brass Photo Frame", "Home Decor", 44.95, 0.35),
    ("Linen Sheet Set Queen", "Bedding", 229.00, 0.48),
    ("Cotton Quilt Cover King", "Bedding", 179.00, 0.46),
    ("Wool Throw Rug", "Bedding", 139.00, 0.50),
    ("Memory Foam Pillow", "Bedding", 89.00, 0.42),
    ("Bamboo Bath Towel Set", "Bedding", 99.00, 0.40),
    ("Weighted Blanket 7kg", "Bedding", 199.00, 0.52),
    ("Outdoor Cushion Covers (2pk)", "Outdoor", 49.95, 0.38),
    ("Teak Folding Chair", "Outdoor", 159.00, 0.55),
    ("Solar Lantern", "Outdoor", 39.00, 0.40),
    ("Herb Garden Kit", "Outdoor", 29.95, 0.30),
    ("Picnic Blanket Waterproof", "Outdoor", 69.00, 0.42),
    ("Hammock with Stand", "Outdoor", 279.00, 0.58),
    ("A5 Linen Notebook", "Stationery", 19.95, 0.25),
    ("Desk Organiser Oak", "Stationery", 54.00, 0.40),
    ("Fountain Pen Set", "Stationery", 79.00, 0.45),
    ("Weekly Planner 2026", "Stationery", 29.00, 0.30),
    ("Washi Tape Set", "Stationery", 12.95, 0.22),
    ("Leather Pencil Case", "Stationery", 39.00, 0.38),
    ("Copper Watering Can", "Outdoor", 74.00, 0.45),          # dead stock, never sells
    ("Marble Coaster Set", "Home Decor", 36.00, 0.35),        # same, never sells
]
NEVER_SOLD = {34, 35}  # keeps these two out of the sales generation below

# Rough month-by-month demand weighting - business picks up toward Nov/Dec
MONTH_W = [7, 6, 7, 7, 8, 8, 7, 8, 8, 9, 13, 15]


def rand_date(lo, hi):
    return lo + timedelta(days=random.randint(0, (hi - lo).days))


def seasonal_date(lo):
    """Pick a 2025 date on/after `lo`, weighted toward the busier months."""
    for _ in range(50):
        m = random.choices(range(1, 13), MONTH_W)[0]
        d = date(2025, m, 1) + timedelta(days=random.randint(0, 27))
        if d >= lo:
            return d
    return rand_date(lo, END)


# products first
products = []
for i, (name, cat, price, cost_share) in enumerate(PRODUCTS, start=1):
    products.append({
        "product_id": i, "product_name": name, "category": cat,
        "unit_price": f"{price:.2f}", "unit_cost": f"{price * cost_share:.2f}",
    })
sellable = [p for p in products if p["product_id"] not in NEVER_SOLD]
# cheaper stuff sells more often, so weight toward that
sell_w = [1 / float(p["unit_price"]) ** 0.5 for p in sellable]

# now the customers
customers = []
N_CUST = 600
for cid in range(1, N_CUST + 1):
    fn, ln = random.choice(FIRST), random.choice(LAST)
    state = random.choices(STATES, STATE_W)[0]
    if random.random() < 0.08:
        state = random.choice(MESSY_STATE[state])
    signup = rand_date(date(2024, 6, 1), date(2025, 11, 30))
    customers.append({
        "customer_id": cid, "first_name": fn, "last_name": ln,
        "email": f"{fn.lower()}.{ln.lower()}{cid}@example.com",
        "state": state,
        "signup_date": "" if random.random() < 0.03 else signup.isoformat(),
        "_signup": signup,
    })

# a few duplicate accounts - same person signed up twice with their email
# cased differently (or with stray whitespace) the second time
for src in random.sample(customers[:N_CUST], 18):
    dup = dict(src)
    dup["customer_id"] = len(customers) + 1
    dup["email"] = src["email"].upper() if random.random() < 0.5 else " " + src["email"]
    later = src["_signup"] + timedelta(days=random.randint(20, 200))
    dup["_signup"] = min(later, date(2025, 11, 30))
    dup["signup_date"] = dup["_signup"].isoformat()
    customers.append(dup)

# and finally orders, their line items, and returns
orders, items, returns = [], [], []
RETURN_RATE = {"Kitchen": 0.04, "Home Decor": 0.07, "Bedding": 0.13,
               "Outdoor": 0.06, "Stationery": 0.02}
REASONS = ["Changed mind", "Damaged in transit", "Not as described",
           "Wrong size", "Faulty", "Arrived late"]
REASON_W = [30, 20, 18, 14, 12, 6]
CHANNELS, CHANNEL_W = ["Web", "App", "Marketplace"], [58, 30, 12]
oid = iid = rid = 0

for c in customers:
    # about 22% of customers never actually place an order; everyone else
    # gets a long-tailed order count (most order once or twice, a few order a lot)
    if random.random() < 0.22:
        continue
    n_orders = min(1 + int(random.expovariate(0.55)), 12)
    lo = max(c["_signup"], START)
    if lo > END:
        continue
    dates = sorted(seasonal_date(lo) for _ in range(n_orders))
    channel_pref = random.choices(CHANNELS, CHANNEL_W)[0]
    for od in dates:
        oid += 1
        status = random.choices(["completed", "cancelled", "pending"], [90, 7, 3])[0]
        if od > date(2025, 12, 24) and random.random() < 0.5:
            status = "pending"
        if random.random() < 0.04:
            status = random.choice([status.upper(), status.capitalize()])
        ch = channel_pref if random.random() < 0.8 else random.choices(CHANNELS, CHANNEL_W)[0]
        orders.append({"order_id": oid, "customer_id": c["customer_id"],
                       "order_date": od.isoformat(), "status": status, "channel": ch})

        if random.random() < 0.012:      # occasionally leave an order with no items at all
            continue
        for p in random.choices(sellable, sell_w, k=random.choices([1, 2, 3, 4], [50, 30, 14, 6])[0]):
            iid += 1
            qty = random.choices([1, 2, 3], [78, 17, 5])[0]
            if random.random() < 0.006:
                qty = random.choice([0, -1])
            disc = random.choices([0, 0.10, 0.20], [80, 14, 6])[0]
            if od.month == 11 and 24 <= od.day <= 30:   # Black Friday week - discounts go up
                disc = max(disc, 0.20)
            items.append({"order_item_id": iid, "order_id": oid,
                          "product_id": p["product_id"], "quantity": qty,
                          "unit_price": p["unit_price"], "discount": f"{disc:.2f}"})
            if status.lower() == "completed" and qty > 0 and random.random() < RETURN_RATE[p["category"]]:
                rid += 1
                rd = od + timedelta(days=random.randint(3, 30))
                returns.append({"return_id": rid, "order_item_id": iid,
                                "return_date": rd.isoformat(),
                                "reason": random.choices(REASONS, REASON_W)[0]})


def write(name, rows, cols):
    with open(os.path.join(OUT, name), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


write("customers.csv", customers, ["customer_id", "first_name", "last_name", "email", "state", "signup_date"])
write("products.csv", products, ["product_id", "product_name", "category", "unit_price", "unit_cost"])
write("orders.csv", orders, ["order_id", "customer_id", "order_date", "status", "channel"])
write("order_items.csv", items, ["order_item_id", "order_id", "product_id", "quantity", "unit_price", "discount"])
write("returns.csv", returns, ["return_id", "order_item_id", "return_date", "reason"])

print(f"customers={len(customers)} products={len(products)} orders={len(orders)} "
      f"order_items={len(items)} returns={len(returns)}")
