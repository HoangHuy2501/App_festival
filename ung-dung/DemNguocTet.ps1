$ErrorActionPreference = 'Stop'

class HolidayOption {
    [string]$Short
    [string]$Label
    [string]$Region
    [string]$DateKey
    [int]$Month
    [int]$Day
    [string[]]$Palette

    HolidayOption([string]$short, [string]$label, [string]$region, [int]$month, [int]$day,
                  [string]$dateKey, [string[]]$palette) {
        $this.Short = $short
        $this.Label = $label
        $this.Region = $region
        $this.DateKey = $dateKey
        $this.Month = $month
        $this.Day = $day
        $this.Palette = $palette
    }
}

class HolidayCalendarEntry {
    [datetime]$Date
    [string]$Name
    [string]$Region

    HolidayCalendarEntry([datetime]$eventDate, [HolidayOption]$holiday) {
        $this.Date = $eventDate
        $this.Name = $holiday.Label
        $this.Region = $holiday.Region
    }
}

function Get-HolidayDateInYear([HolidayOption]$Holiday, [int]$Year) {
    if ($Holiday.DateKey) {
        return $script:variableDates[$Holiday.DateKey][$Year]
    }
    return [datetime]::new($Year, $Holiday.Month, $Holiday.Day)
}

function Get-HolidayDate([HolidayOption]$Holiday, [datetime]$Today) {
    $date = Get-HolidayDateInYear $Holiday $Today.Year
    if ($null -ne $date -and $date -ge $Today) { return $date }
    if ($Today.Year -lt 9999) { return (Get-HolidayDateInYear $Holiday ($Today.Year + 1)) }
}

function Update-CalendarRows {
    if ($null -eq $script:calendarYear.SelectedItem) { return }
    $year = [int]$script:calendarYear.SelectedItem
    $rows = foreach ($holiday in $script:holidays) {
        $date = Get-HolidayDateInYear $holiday $year
        if ($null -ne $date) { [HolidayCalendarEntry]::new($date, $holiday) }
    }
    $script:calendarRows.ItemsSource = @($rows | Sort-Object Date, Name)
}

function Show-HolidayCalendar {
    $layout = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Lich-Ngay-Le.xaml'))
    $calendar = [Windows.Markup.XamlReader]::Parse($layout)
    $calendar.Owner = $script:window
    $script:calendarYear = $calendar.FindName('CalendarYear')
    $script:calendarRows = $calendar.FindName('CalendarRows')
    $script:calendarYear.ItemsSource = @(2026..2035)
    $script:calendarYear.Add_SelectionChanged({ Update-CalendarRows })
    $script:calendarYear.SelectedItem = [Math]::Min(2035, [Math]::Max(2026, [datetime]::Today.Year))
    [void]$calendar.ShowDialog()
    $script:calendarYear = $null
    $script:calendarRows = $null
}

function Update-HolidayTheme {
    $holiday = $script:picker.SelectedItem
    if ($null -eq $holiday) { return }

    for ($index = 0; $index -lt $script:paletteKeys.Count; $index++) {
        $color = [System.Windows.Media.ColorConverter]::ConvertFromString($holiday.Palette[$index])
        $brush = [System.Windows.Media.SolidColorBrush]::new($color)
        $brush.Freeze()
        $script:window.Resources[$script:paletteKeys[$index]] = $brush
    }
}

function Set-CornerPosition {
    if (-not $script:pinnedCorner) { return }

    $interop = [System.Windows.Interop.WindowInteropHelper]::new($script:window)
    $source = [System.Windows.Interop.HwndSource]::FromHwnd($interop.Handle)
    if ($null -eq $source) { return }

    $workArea = [System.Windows.Forms.Screen]::FromHandle($interop.Handle).WorkingArea
    $fromPixels = $source.CompositionTarget.TransformFromDevice
    $topLeft = $fromPixels.Transform([System.Windows.Point]::new($workArea.Left, $workArea.Top))
    $bottomRight = $fromPixels.Transform([System.Windows.Point]::new($workArea.Right, $workArea.Bottom))
    $inset = 12
    $left = if ($script:pinnedCorner.EndsWith('Left')) {
        $topLeft.X + $inset
    } else {
        $bottomRight.X - $script:window.Width - $inset
    }
    $top = if ($script:pinnedCorner.StartsWith('Top')) {
        $topLeft.Y + $inset
    } else {
        $bottomRight.Y - $script:window.Height - $inset
    }

    if ([Math]::Abs($script:window.Left - $left) -gt 0.5) { $script:window.Left = $left }
    if ([Math]::Abs($script:window.Top - $top) -gt 0.5) { $script:window.Top = $top }
}

function Update-PinControls {
    foreach ($entry in $script:cornerMenu.Items) {
        $entry.IsChecked = $entry.Tag -eq $script:pinnedCorner
    }
    $script:pinButton.IsChecked = $script:positionLocked
    $script:pinButton.ToolTip = if ($script:positionLocked) { 'Bỏ ghim vị trí' } else { 'Ghim vị trí hiện tại' }
    $script:dragArea.Cursor = if ($script:positionLocked) {
        [System.Windows.Input.Cursors]::Arrow
    } else {
        [System.Windows.Input.Cursors]::SizeAll
    }
    $script:unpinItem.IsEnabled = $script:positionLocked
}

function Update-Countdown {
    $holiday = $script:picker.SelectedItem
    if ($null -eq $holiday) { return }

    $today = [datetime]::Today
    $target = Get-HolidayDate $holiday $today
    if ($null -eq $target) {
        $count = '—'
        $label = 'hết lịch'
        $hint = if ($holiday.DateKey -eq 'Tet') {
            'Lịch Tết Nguyên đán có dữ liệu đến năm 2050.'
        } else {
            '{0} có dữ liệu từ 2026 đến 2035.' -f $holiday.Label
        }
    } else {
        $daysLeft = ($target - $today).Days
        $count = [string]$daysLeft
        $label = if ($daysLeft -eq 0) { 'hôm nay' } else { 'ngày' }
        $hint = '{0} · {1:dd/MM/yyyy}' -f $holiday.Label, $target
    }

    if ($script:dayCount.Text -ne $count) { $script:dayCount.Text = $count }
    if ($script:dayLabel.Text -ne $label) { $script:dayLabel.Text = $label }
    if ($script:dragArea.ToolTip -ne $hint) { $script:dragArea.ToolTip = $hint }
    $title = "$hint · $count $label"
    if ($script:window.Title -ne $title) { $script:window.Title = $title }
}

$mutex = $null
$timer = $null
try {
    $firstInstance = $false
    $mutex = [System.Threading.Mutex]::new($true, 'Local\DemNguocTetWidget', [ref]$firstInstance)
    if (-not $firstInstance) { return }

    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms
    $script:variableDates = @{}
    foreach ($row in (Import-Csv -LiteralPath (Join-Path $PSScriptRoot 'Lich-Ngay-Le.csv'))) {
        if (-not $script:variableDates.ContainsKey($row.Key)) {
            $script:variableDates[$row.Key] = @{}
        }
        $date = [datetime]::ParseExact($row.Date, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
        $script:variableDates[$row.Key][$date.Year] = $date
    }

    $script:paletteKeys = @('CardBrush', 'BorderBrush', 'PickerBrush', 'PickerHoverBrush',
        'AccentBrush', 'TextBrush')
    $script:holidays = @(
        [HolidayOption]::new('Tết', 'Tết Nguyên đán', 'Việt Nam', 0, 0, 'Tet',
            @('#621F2B', '#B65C53', '#812F3B', '#9C3E48', '#FFE2A8', '#FFF1E2'))
        [HolidayOption]::new('Giỗ', 'Giỗ Tổ Hùng Vương', 'Việt Nam', 0, 0, 'HungKings',
            @('#4F3023', '#A67858', '#66432D', '#7D523A', '#FFE3A8', '#FFF1D9'))
        [HolidayOption]::new('30/4', 'Ngày Giải phóng miền Nam, thống nhất đất nước', 'Việt Nam', 4, 30, '',
            @('#6B331E', '#C27C52', '#89492A', '#A75936', '#FFD5A5', '#FFF2DD'))
        [HolidayOption]::new('1/6', 'Ngày Quốc tế Thiếu nhi tại Việt Nam', 'Việt Nam', 6, 1, '',
            @('#37496B', '#799FC4', '#40577C', '#4C638B', '#FFE7A6', '#EFF8FF'))
        [HolidayOption]::new('28/6', 'Ngày Gia đình Việt Nam', 'Việt Nam', 6, 28, '',
            @('#4C3545', '#AD7A9C', '#63445B', '#76516D', '#FFDAE6', '#FFF2F7'))
        [HolidayOption]::new('2/9', 'Quốc khánh Việt Nam', 'Việt Nam', 9, 2, '',
            @('#861B24', '#DE7766', '#A02830', '#BD383E', '#FFF278', '#FFF7DB'))
        [HolidayOption]::new('Thu', 'Tết Trung Thu', 'Việt Nam', 0, 0, 'MidAutumn',
            @('#332951', '#8E78BD', '#493869', '#5A4682', '#FFE6A1', '#FFF2D9'))
        [HolidayOption]::new('20/10', 'Ngày Phụ nữ Việt Nam', 'Việt Nam', 10, 20, '',
            @('#602B48', '#B26D99', '#783955', '#92476B', '#FFD0E4', '#FFF0F8'))
        [HolidayOption]::new('20/11', 'Ngày Nhà giáo Việt Nam', 'Việt Nam', 11, 20, '',
            @('#223D56', '#7292AA', '#304D66', '#405F78', '#FFE0A6', '#F0FAFF'))
        [HolidayOption]::new('24/11', 'Ngày Văn hóa Việt Nam', 'Việt Nam', 11, 24, '',
            @('#523723', '#BB8A65', '#69492F', '#815A3F', '#FFE6B5', '#FFF5E7'))
        [HolidayOption]::new('1/1', 'Tết Dương lịch', 'Thế giới', 1, 1, '',
            @('#202A56', '#687CBF', '#303E70', '#40528D', '#C9DBFF', '#F0F4FF'))
        [HolidayOption]::new('14/2', 'Valentine', 'Thế giới', 2, 14, '',
            @('#6A2440', '#C47399', '#823456', '#994368', '#FFD1DC', '#FFF3F8'))
        [HolidayOption]::new('8/3', 'Ngày Quốc tế Phụ nữ', 'Thế giới', 3, 8, '',
            @('#522650', '#AD76AE', '#69356A', '#824782', '#EFD5FF', '#FFF2FF'))
        [HolidayOption]::new('PS', 'Lễ Phục Sinh (Tây phương)', 'Thế giới', 0, 0, 'Easter',
            @('#324B3D', '#769A80', '#3E5A49', '#4C6856', '#FFE6BE', '#F0FFF3'))
        [HolidayOption]::new('22/4', 'Ngày Trái Đất', 'Thế giới', 4, 22, '',
            @('#23484B', '#68989A', '#2C5A5A', '#376A6C', '#C7F8D2', '#E9FFFF'))
        [HolidayOption]::new('1/5', 'Ngày Quốc tế Lao động', 'Thế giới', 5, 1, '',
            @('#352851', '#9178BA', '#4A3869', '#5D4880', '#E1CAFF', '#F8F0FF'))
        [HolidayOption]::new('5/6', 'Ngày Môi trường Thế giới', 'Thế giới', 6, 5, '',
            @('#314622', '#8FA26F', '#40582D', '#52693C', '#D9F7A9', '#F3FFE7'))
        [HolidayOption]::new('24/10', 'Ngày Liên Hợp Quốc', 'Thế giới', 10, 24, '',
            @('#1D416C', '#6E9BD1', '#285283', '#376499', '#CCE8FF', '#EDF7FF'))
        [HolidayOption]::new('Hlw', 'Halloween', 'Thế giới', 10, 31, '',
            @('#402634', '#B07259', '#563545', '#704356', '#FFC57C', '#FFF3E7'))
        [HolidayOption]::new('Noel', 'Giáng sinh', 'Thế giới', 12, 25, '',
            @('#164637', '#5E9C83', '#225F4C', '#2C715A', '#FFDF9C', '#EBFFF6'))
        [HolidayOption]::new('31/12', 'Giao thừa Dương lịch', 'Thế giới', 12, 31, '',
            @('#302B47', '#8276A5', '#45395E', '#554971', '#FFE4AE', '#F8F1FF'))
    )

    $layout = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Widget.xaml'))
    $script:window = [Windows.Markup.XamlReader]::Parse($layout)
    $script:picker = $script:window.FindName('HolidayPicker')
    $script:dayCount = $script:window.FindName('DayCount')
    $script:dayLabel = $script:window.FindName('DayLabel')
    $script:dragArea = $script:window.FindName('DragArea')
    $script:pinButton = $script:window.FindName('PinButton')

    $workArea = [Windows.SystemParameters]::WorkArea
    $script:window.Left = $workArea.Right - $script:window.Width - 20
    $script:window.Top = $workArea.Top + 20

    $menu = [Windows.Controls.ContextMenu]::new()
    $script:pinnedCorner = ''
    $script:positionLocked = $false
    $script:pinButton.Add_Click({
        $script:pinnedCorner = ''
        $script:positionLocked = [bool]$script:pinButton.IsChecked
        Update-PinControls
    })
    $script:cornerMenu = [Windows.Controls.MenuItem]::new()
    $script:cornerMenu.Header = 'Ghim vào góc'
    $cornerLabels = [ordered]@{
        TopLeft = 'Trên trái'
        TopRight = 'Trên phải'
        BottomLeft = 'Dưới trái'
        BottomRight = 'Dưới phải'
    }
    foreach ($corner in $cornerLabels.Keys) {
        $item = [Windows.Controls.MenuItem]::new()
        $item.Header = $cornerLabels[$corner]
        $item.Tag = $corner
        $item.IsCheckable = $true
        $item.Add_Click({
            param($sender, $eventArgs)
            $script:pinnedCorner = $sender.Tag
            $script:positionLocked = $true
            Set-CornerPosition
            Update-PinControls
        })
        [void]$script:cornerMenu.Items.Add($item)
    }
    [void]$menu.Items.Add($script:cornerMenu)

    $script:unpinItem = [Windows.Controls.MenuItem]::new()
    $script:unpinItem.Header = 'Bỏ ghim để kéo'
    $script:unpinItem.Add_Click({
        $script:pinnedCorner = ''
        $script:positionLocked = $false
        Update-PinControls
    })
    [void]$menu.Items.Add($script:unpinItem)
    [void]$menu.Items.Add([Windows.Controls.Separator]::new())
    $calendarItem = [Windows.Controls.MenuItem]::new()
    $calendarItem.Header = 'Lịch ngày lễ 2026–2035'
    $calendarItem.Add_Click({ Show-HolidayCalendar })
    [void]$menu.Items.Add($calendarItem)
    Update-PinControls

    $close = [Windows.Controls.MenuItem]::new()
    $close.Header = 'Thoát'
    $close.Add_Click({ $script:window.Close() })
    [void]$menu.Items.Add($close)
    $script:dragArea.ContextMenu = $menu
    $script:dragArea.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        if (-not $script:positionLocked -and
            $eventArgs.LeftButton -eq [Windows.Input.MouseButtonState]::Pressed) {
            $script:window.DragMove()
        }
    })

    $script:picker.ItemsSource = $script:holidays
    $script:picker.Add_SelectionChanged({
        Update-HolidayTheme
        Update-Countdown
    })
    $script:picker.SelectedIndex = 0

    $timer = [Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [TimeSpan]::FromSeconds(1)
    $timer.Add_Tick({
        Update-Countdown
        Set-CornerPosition
    })
    $timer.Start()
    [void]$script:window.ShowDialog()
} catch {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show($_.Exception.Message, 'Không mở được Widget Đếm ngược Tết')
} finally {
    if ($null -ne $timer) { $timer.Stop() }
    if ($null -ne $mutex) {
        if ($firstInstance) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
