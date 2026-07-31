# 💧 AquaFlow

A modern Flutter-based water delivery management platform built for water bottle distribution businesses.

AquaFlow connects **Customers**, **Vendors**, **Delivery Riders**, and **Administrators** in a single application powered by **Supabase**.

---

## ✨ Features

### 👤 Customer
- Browse products
- Search & filter catalog
- Shopping cart
- Address management
- Google Maps location picker
- Secure checkout
- Real-time order tracking
- Order history
- Favorites

### 🏪 Vendor
- Dashboard & analytics
- Product management (CRUD)
- Order management
- Rider assignment
- Customer registration
- Business profile management

### 🚚 Rider
- Delivery management
- Live location sharing
- Delivery status updates
- Navigation support
- Delivery history

### 🛠️ Admin
- Vendor management
- Rider management
- Customer management
- Platform monitoring
- Business analytics

---

## 🚀 Tech Stack

- **Flutter**
- **Dart**
- **Supabase**
  - Authentication
  - PostgreSQL
  - Storage
  - Realtime
- **Riverpod**
- **GoRouter**
- **Google Maps**
- **Firebase Cloud Messaging**
- **Hive**
- **Material 3**

---

## 📂 Project Structure

```text
lib/
├── core/
├── shared/
├── features/
│   ├── authentication/
│   ├── customer/
│   ├── vendor/
│   ├── rider/
│   ├── admin/
│   ├── cart/
│   ├── orders/
│   └── addresses/

supabase/
├── migrations/
└── seed/
```

---

## ⚙️ Getting Started

### Prerequisites

- Flutter 3.24+
- Android Studio / VS Code
- Java 17+
- Supabase Project
- Google Maps API Key

### Installation

Clone the repository

```bash
git clone https://github.com/yourusername/aquaflow.git
cd aquaflow
```

Install dependencies

```bash
flutter pub get
```

Create a `.env` file

```env
SUPABASE_URL=YOUR_URL
SUPABASE_ANON_KEY=YOUR_KEY
GOOGLE_MAPS_API_KEY=YOUR_KEY
```

Run database migrations inside Supabase.

Start the application

```bash
flutter run
```

For Web

```bash
flutter run -d chrome
```

---

## To build apps for role based access
flutter build apk --dart-define=FLAVOR=customer
flutter build apk --dart-define=FLAVOR=vendor
flutter build apk --dart-define=FLAVOR=rider


## 🗄️ Backend

Supabase powers:

- Authentication
- Database
- Row Level Security (RLS)
- Storage
- Realtime Updates

---

## 📱 Supported Platforms

- ✅ Android
- ✅ Web
- 🚧 iOS
- 🚧 Desktop

---

## 📸 Screens

- Customer App
- Vendor Dashboard
- Rider App
- Admin Dashboard

> Add screenshots inside the `screenshots/` folder.

---

## 🔒 Security

- Row Level Security (RLS)
- Role-based Authentication
- Secure API Access
- Protected Storage

---

## 🛣️ Roadmap

- Payment Gateway Integration
- Wallet System
- Coupons & Promotions
- Push Notifications
- In-app Chat
- Subscription Plans
- Advanced Analytics

---

## 🤝 Contributing

Contributions are welcome.

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Open a Pull Request

---

## 📄 License

This project is licensed under the **MIT License**.

---

## 👨‍💻 Developed By

**Mudassar Shabbir**

## 👨‍💻 Supervised By

**Sir Ibrahim**

Built with ❤️ using Flutter & Supabase.


