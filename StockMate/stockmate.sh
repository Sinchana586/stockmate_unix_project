
#!/bin/bash

# ==========================================
# STOCKMATE - INVENTORY MANAGEMENT SYSTEM
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="$SCRIPT_DIR/data"
REPORT_DIR="$SCRIPT_DIR/reports"
BACKUP_DIR="$SCRIPT_DIR/backups"

PRODUCT_FILE="$DATA_DIR/products.csv"
TRANSACTION_FILE="$DATA_DIR/transactions.csv"

# ---------- INITIALIZATION ----------

initialize() {
    mkdir -p "$DATA_DIR" "$REPORT_DIR" "$BACKUP_DIR"

    if [ ! -f "$PRODUCT_FILE" ]; then
        echo "ID,Name,Category,Price,Quantity,MinStock,ExpiryDate" > "$PRODUCT_FILE"
    fi

    if [ ! -f "$TRANSACTION_FILE" ]; then
        echo "TransactionID,ProductID,Type,Quantity,Date" > "$TRANSACTION_FILE"
    fi
}

pause_screen() {
    echo
    read -r -p "Press Enter to continue..."
}

valid_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

valid_price() {
    [[ "$1" =~ ^[0-9]+([.][0-9]{1,2})?$ ]]
}

valid_expiry() {
    [[ "$1" == "N/A" || "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

# ---------- PRODUCT FUNCTIONS ----------

product_exists() {
    grep -q "^$1," "$PRODUCT_FILE"
}

add_product() {
    local id name category price quantity minimum expiry

    echo
    echo "========== ADD NEW PRODUCT =========="

    read -r -p "Product ID: " id

    if ! valid_number "$id"; then
        echo "Invalid product ID."
        return
    fi

    if product_exists "$id"; then
        echo "Product ID already exists."
        return
    fi

    read -r -p "Product Name: " name
    read -r -p "Category: " category
    read -r -p "Price: " price
    read -r -p "Quantity: " quantity
    read -r -p "Minimum Stock Level: " minimum
    read -r -p "Expiry Date (YYYY-MM-DD or N/A): " expiry

    if [[ -z "$name" || -z "$category" || "$name" == *,* || "$category" == *,* ]]; then
        echo "Invalid product name or category."
        return
    fi

    if ! valid_price "$price" ||
       ! valid_number "$quantity" ||
       ! valid_number "$minimum" ||
       ! valid_expiry "$expiry"; then
        echo "Invalid input. Please check price, quantity, minimum stock and expiry."
        return
    fi

    # Ensure the previous record ends with a newline
    if [[ -s "$PRODUCT_FILE" ]]; then
        last_char=$(tail -c 1 "$PRODUCT_FILE" | od -An -t x1 | tr -d '[:space:]')

        if [[ "$last_char" != "0a" ]]; then
            printf '\n' >> "$PRODUCT_FILE"
        fi
    fi

# Append the new product on a separate line
    printf '%s,%s,%s,%s,%s,%s,%s\n' \
        "$id" "$name" "$category" "$price" "$quantity" "$minimum" "$expiry" >> "$PRODUCT_FILE"

    echo "Product added successfully!"

    echo "Product added successfully!"
}

view_products() {
    echo
    echo "========== ALL PRODUCTS =========="

    if [ "$(wc -l < "$PRODUCT_FILE")" -le 1 ]; then
        echo "No products available."
        return
    fi

    column -s, -t "$PRODUCT_FILE" 2>/dev/null || cat "$PRODUCT_FILE"
}

search_product() {
    local id

    echo
    read -r -p "Enter Product ID to search: " id

    if product_exists "$id"; then
        grep "^$id," "$PRODUCT_FILE"
    else
        echo "Product not found."
    fi
}

update_product() {
    local id new_name new_category new_price new_min new_expiry
    local temp_file found=0

    echo
    read -r -p "Enter Product ID to update: " id

    if ! product_exists "$id"; then
        echo "Product not found."
        return
    fi

    read -r -p "New Name: " new_name
    read -r -p "New Category: " new_category
    read -r -p "New Price: " new_price
    read -r -p "New Minimum Stock: " new_min
    read -r -p "New Expiry Date (YYYY-MM-DD or N/A): " new_expiry

    if [[ -z "$new_name" || -z "$new_category" ||
          "$new_name" == *,* || "$new_category" == *,* ]] ||
       ! valid_price "$new_price" ||
       ! valid_number "$new_min" ||
       ! valid_expiry "$new_expiry"; then
        echo "Invalid input. Update cancelled."
        return
    fi

    temp_file=$(mktemp)

    head -n 1 "$PRODUCT_FILE" > "$temp_file"

    while IFS=, read -r pid name category price qty minimum expiry
    do
        if [[ "$pid" == "$id" ]]; then
            echo "$pid,$new_name,$new_category,$new_price,$qty,$new_min,$new_expiry" >> "$temp_file"
            found=1
        else
            echo "$pid,$name,$category,$price,$qty,$minimum,$expiry" >> "$temp_file"
        fi
    done < <(tail -n +2 "$PRODUCT_FILE")

    mv "$temp_file" "$PRODUCT_FILE"

    echo "Product updated successfully."
}

delete_product() {
    local id temp_file answer

    echo
    read -r -p "Enter Product ID to delete: " id

    if ! product_exists "$id"; then
        echo "Product not found."
        return
    fi

    read -r -p "Confirm deletion? (y/n): " answer

    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        echo "Deletion cancelled."
        return
    fi

    temp_file=$(mktemp)

    head -n 1 "$PRODUCT_FILE" > "$temp_file"
    grep -v "^$id," "$PRODUCT_FILE" | tail -n +2 >> "$temp_file"

    mv "$temp_file" "$PRODUCT_FILE"

    echo "Product deleted successfully."
}

# ---------- STOCK MANAGEMENT ----------

stock_operation() {
    local id type amount
    local temp_file found=0

    echo
    echo "1. Stock In"
    echo "2. Stock Out"

    read -r -p "Choose operation: " type

    case "$type" in
        1) type="STOCK_IN" ;;
        2) type="STOCK_OUT" ;;
        *)
            echo "Invalid choice."
            return
            ;;
    esac

    read -r -p "Enter Product ID: " id

    if ! product_exists "$id"; then
        echo "Product not found."
        return
    fi

    read -r -p "Enter Quantity: " amount

    if ! valid_number "$amount" || (( amount <= 0 )); then
        echo "Enter a valid positive quantity."
        return
    fi

    temp_file=$(mktemp)

    head -n 1 "$PRODUCT_FILE" > "$temp_file"

    while IFS=, read -r pid name category price qty minimum expiry
    do
        if [[ "$pid" == "$id" ]]; then
            if [[ "$type" == "STOCK_IN" ]]; then
                qty=$((qty + amount))
            else
                if (( amount > qty )); then
                    echo "Insufficient stock available."
                    rm -f "$temp_file"
                    return
                fi

                qty=$((qty - amount))
            fi

            found=1
        fi

        echo "$pid,$name,$category,$price,$qty,$minimum,$expiry" >> "$temp_file"

    done < <(tail -n +2 "$PRODUCT_FILE")

    if (( found == 1 )); then
        mv "$temp_file" "$PRODUCT_FILE"

        local transaction_id
        transaction_id="$(date +%Y%m%d%H%M%S)-$RANDOM"

        echo "$transaction_id,$id,$type,$amount,$(date '+%Y-%m-%d %H:%M:%S')" >> "$TRANSACTION_FILE"

        echo "$type completed successfully!"
    else
        rm -f "$temp_file"
        echo "Product not found."
    fi
}

view_transactions() {
    echo
    echo "========== TRANSACTION HISTORY =========="

    if [ "$(wc -l < "$TRANSACTION_FILE")" -le 1 ]; then
        echo "No transactions recorded."
        return
    fi

    column -s, -t "$TRANSACTION_FILE" 2>/dev/null || cat "$TRANSACTION_FILE"
}

# ---------- INVENTORY ANALYSIS ----------

low_stock_alert() {
    local found=0

    echo
    echo "========== LOW STOCK ALERTS =========="

    while IFS=, read -r id name category price qty minimum expiry
    do
        if [[ "$id" == "ID" ]]; then
            continue
        fi

        if (( qty <= minimum )); then
            echo "ALERT: $name | Available: $qty | Minimum: $minimum"
            found=1
        fi

    done < "$PRODUCT_FILE"

    if (( found == 0 )); then
        echo "All products have sufficient stock."
    fi
}

inventory_valuation() {
    echo
    echo "========== INVENTORY VALUATION =========="

    awk -F, '
    NR > 1 {
        total += $4 * $5
    }
    END {
        printf "Total Inventory Value: Rs. %.2f\n", total
    }' "$PRODUCT_FILE"
}

expiry_alert() {
    local today found=0

    today=$(date +%F)

    echo
    echo "========== EXPIRY ALERTS =========="

    while IFS=, read -r id name category price qty minimum expiry
    do
        if [[ "$id" == "ID" || "$expiry" == "N/A" ]]; then
            continue
        fi

        if [[ "$expiry" < "$today" || "$expiry" == "$today" ]]; then
            echo "EXPIRED: $name | Expiry: $expiry"
            found=1
        elif [[ "$expiry" < "$(date -d '+30 days' +%F)" ]]; then
            echo "EXPIRING SOON: $name | Expiry: $expiry"
            found=1
        fi

    done < "$PRODUCT_FILE"

    if (( found == 0 )); then
        echo "No expired or soon-to-expire products found."
    fi
}

# ---------- REPORTS AND BACKUP ----------

generate_report() {
    local report_file

    report_file="$REPORT_DIR/inventory_report_$(date +%Y%m%d_%H%M%S).txt"

    {
        echo "========== STOCKMATE INVENTORY REPORT =========="
        echo "Generated: $(date)"
        echo
        cat "$PRODUCT_FILE"
        echo
        echo "========== INVENTORY VALUE =========="

        awk -F, 'NR > 1 {
            total += $4 * $5
        }
        END {
            printf "Total Value: Rs. %.2f\n", total
        }' "$PRODUCT_FILE"

        echo
        echo "========== TRANSACTION HISTORY =========="
        cat "$TRANSACTION_FILE"

    } > "$report_file"

    echo "Report generated: $report_file"
}

backup_data() {
    local backup_name

    backup_name="backup_$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$BACKUP_DIR/$backup_name"

    cp "$PRODUCT_FILE" "$TRANSACTION_FILE" "$BACKUP_DIR/$backup_name/"

    echo "Backup created successfully!"
    echo "Location: $BACKUP_DIR/$backup_name"
}

# ---------- MAIN MENU ----------

main_menu() {

    while true
    do
        clear

        echo "=========================================="
        echo "              STOCKMATE"
        echo "       INVENTORY MANAGEMENT SYSTEM"
        echo "=========================================="

        echo "1.  Add New Product"
        echo "2.  View All Products"
        echo "3.  Search Product"
        echo "4.  Update Product"
        echo "5.  Delete Product"
        echo "6.  Stock In / Stock Out"
        echo "7.  View Transaction History"
        echo "8.  Low Stock Alerts"
        echo "9.  Inventory Valuation"
        echo "10. Expiry Alerts"
        echo "11. Generate Inventory Report"
        echo "12. Backup Inventory Data"
        echo "13. Exit"

        echo "=========================================="

        read -r -p "Enter your choice: " choice

        case "$choice" in
            1) add_product; pause_screen ;;
            2) view_products; pause_screen ;;
            3) search_product; pause_screen ;;
            4) update_product; pause_screen ;;
            5) delete_product; pause_screen ;;
            6) stock_operation; pause_screen ;;
            7) view_transactions; pause_screen ;;
            8) low_stock_alert; pause_screen ;;
            9) inventory_valuation; pause_screen ;;
            10) expiry_alert; pause_screen ;;
            11) generate_report; pause_screen ;;
            12) backup_data; pause_screen ;;
            13)
                echo "Thank you for using StockMate!"
                exit 0
                ;;
            *)
                echo "Invalid choice. Try again."
                pause_screen
                ;;
        esac
    done
}

# ---------- PROGRAM START ----------

initialize
main_menu
